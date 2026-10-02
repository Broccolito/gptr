# Track 03 — Pi unified LLM API, provider wire formats, OAuth subscription auth

Research date: 2026-09-29. Researcher: track-03 sub-agent.
Primary source: Pi monorepo clone at commit `1b347794e2a630e4359f2584f4eea388145d0ddf`
(2026-09-29), package `@earendil-works/pi-ai` version `0.99.1`
(`packages/ai/package.json`). All `packages/...` paths below are relative to the
clone root
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi`.
Prototype code lives (temporarily) in
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-03/`
and is reproduced in full in section 5 because the scratch directory is
session scoped.

Claim labels: **VERIFIED** = I read the cited source lines / fetched the URL /
executed the command myself. **LIKELY** = strong indirect evidence.
**UNCERTAIN** = could not be confirmed.

Naming convention in this report: Pi names are written as in the TypeScript
source (`stopReason`, `toolCall`); proposed R names are snake_case
(`stop_reason`, `tool_call`). A mapping table is in section 4.2.

---

## 1. Executive summary

1. **pi-ai is three layers**: plain-data `Model` records (catalog), per-provider
   `Provider` objects (id, base URL, auth, model list), and per-wire-format "API"
   adapters that turn a provider-neutral `Context` into an HTTP request and
   turn the provider's stream into 12 normalised event types ending in one
   `AssistantMessage`. (VERIFIED: `packages/ai/src/types.ts`, `models.ts`.)
2. **42 providers, 10 chat wire formats.** 26 of the 42 providers serve at
   least part of their catalog over `openai-completions`; the four formats gptr
   needs for REQ-11 are
   `anthropic-messages`, `openai-responses`, `openai-completions`,
   `google-generative-ai`. Everything provider specific is data
   (`baseUrl`, `compat` flags, `thinkingLevelMap`, `headers`), not code.
   (VERIFIED: section 2.4 table, built from source plus the live catalog.)
3. **All four formats are plain HTTPS + Server-Sent Events.** Pi uses vendor
   SDKs for request plumbing but already parses Anthropic and Codex SSE by
   hand (`anthropic-messages.ts:319-509`, `openai-codex-responses.ts:799-859`).
   A pure-R implementation on httr2/curl + jsonlite is feasible; section 5
   contains working, tested R code for the SSE decoder, the four normalisers,
   the incremental tool-argument JSON parser, request builders, cost,
   cross-provider hand-off, PKCE/loopback/device-code OAuth and a locked
   credential store. (VERIFIED by execution.)
4. **Event protocol**: `start`, `text_start|delta|end`,
   `thinking_start|delta|end`, `toolcall_start|delta|end`, then exactly one of
   `done` (reason `stop|length|toolUse|deferred`) or `error` (reason
   `error|aborted`). Failures never throw once a stream exists; they arrive as an
   `error` event carrying the partial message. (VERIFIED: `types.ts:752-783`.)
5. **Partial tool-call JSON**: every adapter appends the argument delta to a
   scratch string and re-parses it with `parseStreamingJson()` = strict
   `JSON.parse` -> control-character/escape repair -> npm `partial-json`
   (Allow.ALL) -> `{}`. The scratch buffer is deleted at `toolcall_end`.
   (VERIFIED: `utils/json-parse.ts:104-124`.) The R port is incremental
   (each byte scanned once) and roughly 13-18x faster than naive re-scanning
   on a 180 KB argument streamed in 2000 deltas (two runs: 0.22 s vs 3.98 s
   = 18x and 0.45 s vs 5.77 s = 13x; the second run is the output shown in
   section 5.2; verifier re-run: 0.21 s vs 2.99 s = 14x).
6. **Cross-provider hand-off** is one function, `transformMessages()`: foreign
   thinking blocks become plain text (no tags), redacted/encrypted thinking and
   Gemini thought signatures are dropped when the target model differs, tool
   call ids are normalised per target API (Anthropic `^[a-zA-Z0-9_-]{1,64}$`,
   OpenAI chat 40 chars, Mistral 9 alphanumerics), errored/aborted assistant
   turns are skipped, and orphaned tool calls get a synthetic
   `"No result provided"` error result. (VERIFIED:
   `api/transform-messages.ts:64-235`.)
7. **Thinking levels** are one enum (`minimal|low|medium|high|xhigh|max`, plus
   `off`) mapped per model through `thinkingLevelMap` (string = provider value,
   `null` = unsupported, missing = default) and per API into `effort`,
   `budget_tokens`, `thinkingLevel`, `reasoning.effort`, `enable_thinking`, ...
   Default budgets: minimal 1024, low 2048, medium 8192, high 16384 tokens.
   (VERIFIED: `models.ts:1215-1247`, `api/simple-options.ts:54-92`.)
8. **Cost** = tokens x USD-per-million rates from the catalog, with request-wide
   context tiers (`inputTokensAbove`) and the Anthropic rule "1h cache writes
   cost 2x base input". OpenAI-style usage must first subtract cached tokens
   from `prompt_tokens`/`input_tokens`. (VERIFIED: `models.ts:1193-1213`,
   `openai-completions.ts:1511-1552`.)
9. **Model catalog**: generated at build time from `https://models.dev/api.json`
   (plus OpenRouter, Vercel AI Gateway, NVIDIA and Radius listings, processed by
   a 3,680-line generator script that is mostly hand-written corrections),
   shipped as JSON; refreshed at run time
   from `https://pi.dev/api/models/providers/{id}` with `If-None-Match`/ETag,
   at most every 4 hours, disabled by `PI_OFFLINE`. (VERIFIED: source +
   executed fetches, section 2.10.)
10. **Auth resolution order**: explicit per-request key -> stored credential in
    `~/.pi/agent/auth.json` -> `models.json` key -> environment variable ->
    ambient cloud credentials. OAuth tokens are refreshed under a file lock when
    less than 5 minutes of validity remain. (VERIFIED: `auth/resolve.ts`,
    `coding-agent/docs/models.md:23`.)
11. **OAuth flows in the source**: Anthropic (PKCE + loopback 53692), OpenAI
    "Sign in with ChatGPT" (PKCE + loopback 1455 + dynamic client
    registration), OpenAI Codex legacy (PKCE + loopback 1455 or device code),
    GitHub Copilot (device code), OpenRouter (PKCE, returns a permanent API
    key), xAI, Kimi, Meta (device code), Radius (Pi's own gateway). Google
    Gemini CLI / Antigravity OAuth was **removed** from Pi
    (`packages/ai/CHANGELOG.md:1025`). (VERIFIED.)
12. **Anthropic subscription tokens are used by Pi in "stealth mode"**: the
    adapter impersonates Claude Code (user agent, `x-app: cli`, beta flags,
    mandatory "You are Claude Code..." system block, tool names re-cased to
    Claude Code's). Anthropic's published policy says OAuth from
    Free/Pro/Max plans is for Claude Code and native Anthropic apps only and that
    third-party developers may not route requests through those credentials.
    **Recommendation: gptr must not reimplement this.** Use the Claude plan only
    through the unmodified `claude` binary (`claude -p`). The policy says it
    does not prevent "an end user from signing in to the unmodified Claude
    Code binary with their own Claude subscription"; it also says that
    "preinstalling or running Claude Code in your products or services"
    requires agreeing to the Commercial Terms of Service, an unmodified
    binary, and per-user authentication. Whether an open-source R package that
    drives the user's own locally installed `claude` falls under that clause is
    UNCERTAIN (not stated); treat the bridge as "allowed for the end user's own
    login, not sanctioned for gptr to broker". (VERIFIED:
    `anthropic-messages.ts:86-123, 949-968, 1025, 1085-1100`;
    https://code.claude.com/docs/en/legal-and-compliance, re-fetched raw by the
    verifier.)
13. **OpenAI has an official route for open-source tools**: "Sign in with
    ChatGPT - ChatGPT plan usage for open-source and locally hosted apps"
    (dynamic client registration, PKCE, loopback `127.0.0.1`, token used as
    Bearer against `https://api.openai.com/v1/responses` with `store:false`,
    `stream:true`). Pi implements it (`auth/oauth/openai-chatgpt.ts`). This is
    a native, pure-R-implementable way to satisfy the ChatGPT half of REQ-12,
    alongside shelling out to `codex exec --json`. (VERIFIED: source +
    https://developers.openai.com/siwc/token-sharing-open-source/sign-in.)
14. **Jev / System One is already in Pi** as a third model type ("classifier")
    with API `typesafe-system-one`: `POST {baseUrl}/systemone`, Bearer key
    `TYPESAFE_API_KEY`, body `{model, state, questions}`, answers with
    probabilities. Wire type for booleans is `noul`. (VERIFIED:
    `api/system-one-shared.ts`, `api/typesafe-system-one.ts`.)
15. **Recommended R stack**: Imports `httr2`, `curl`, `jsonlite`, `openssl`,
    `rlang`, `cli`; Suggests `httpuv` (loopback OAuth), `later`/`promises`
    (async), `keyring`, `processx` (CLI bridges). No compiled code in gptr.
16. **Measured R performance** (R 4.4.3, macOS, C locale): SSE decode +
    Anthropic normaliser 8,700-13,100 events/s (two runs, machine under load
    in the slower one); three concurrent streams multiplexed
    in one R process with `curl::multi_run()`; first event 0.33 s after request
    start on a server that trickles 23 bytes every 15 ms (true incremental
    streaming). (VERIFIED by execution, section 5.)
17. **Biggest pitfalls found**: `httr2::req_timeout()` is a *total* transfer
    timeout (kills long streams; use `connecttimeout` + `low_speed_time`);
    jsonlite turns `list()` into `[]` (tool arguments and `properties` must be
    *named* empty lists to become `{}`); length-1 vectors are unboxed (use
    `list("x")` for `required`); integers above 2^53 lose precision; consecutive
    tool results must be merged into one user message for Anthropic and Gemini.

---

## 2. Findings

### 2.1 Architecture of pi-ai

| Layer | What it is | Source |
|---|---|---|
| `Model<TApi>` | Plain serialisable record: id, name, api, provider, baseUrl, input modalities, cost, contextWindow, maxTokens, reasoning, thinkingLevelMap, compat, headers | `packages/ai/src/types.ts:1097-1142` |
| `Provider` | Runtime unit: id, name, baseUrl, headers, `auth` (`apiKey` and/or `oauth`), `getModels()`, optional `refreshModels()`, `filterModels()`, `stream()`, `streamSimple()`, optional `classify()`, `generateImages()` | `packages/ai/src/models.ts:144-233` |
| `Models` | Collection of providers; resolves auth, merges headers, dispatches a request to the provider that owns the model | `packages/ai/src/models.ts:244-353, 384-983` |
| API module | One per wire format under `packages/ai/src/api/`; exports `stream(model, context, options)` (provider-specific options) and `streamSimple(model, context, options)` (unified `reasoning` level) | `packages/ai/src/types.ts:286-299` |
| `createProvider()` | Builds a provider from parts; a single `api` or a map keyed by `model.api` for mixed-API providers (GitHub Copilot, OpenCode, OpenRouter, Fireworks, Cloudflare AI Gateway) | `packages/ai/src/models.ts:1034-1175` |
| Event stream | `AssistantMessageEventStream`: push queue + async iterator + `result()` promise resolved by the terminal event | `packages/ai/src/utils/event-stream.ts:26-110` |

Facts (all VERIFIED by reading the cited lines):

- `stream()` vs `streamSimple()`: `streamSimple` takes the unified
  `SimpleStreamOptions` (`reasoning`, `toolChoice: "auto"|"none"`,
  `thinkingBudgets`) and translates them into the API's own options, then
  calls `stream`. gptr only needs the `streamSimple` semantics.
- Request options shared by all APIs (`types.ts:132-237`): `signal`, `apiKey`,
  `fetch`, `env`, `onPayload` (inspect/replace the request body),
  `onResponse` (status + headers), `onProviderStreamEvent` (raw provider
  event), `headers` (null suppresses a default header), `timeoutMs`,
  `maxRetries`, `maxRetryDelayMs` (default 60000), `temperature`,
  `samplingParams`, `maxTokens`, `transport`, `cacheRetention`
  (`none|short|long`, default `short`), `sessionId`, `metadata`.
- `Context` is `{systemPrompt?, messages, tools?}`; `normalizeContext()` folds
  the prompt and tools into a leading `system` message, and later `system`
  messages in the transcript can add instructions, patch named prompt sections
  and add/remove tools. Adapters either send those in place (models with
  `supportsMidConvoSystemMessages`) or collapse them into the leading prompt
  (`utils/transcript.ts:30-34, 108-120`). gptr v1 can ignore the
  mid-conversation machinery and always collapse.
- Pi pins vendor SDKs (`@anthropic-ai/sdk 0.124.0`, `openai 7.19.0`,
  `@google/genai 2.21.0`, `@aws-sdk/client-bedrock-runtime`) but calls them with
  `maxRetries: 0` and wraps requests in its own interruptible retry helper
  (`utils/provider-retry.ts:105-125`).

### 2.2 Unified message model

Verbatim types are in section 3.1. Summary (VERIFIED, `types.ts`):

- Content blocks: `text` (`text`, optional `textSignature`), `thinking`
  (`thinking`, optional `thinkingSignature`, optional `redacted`), `image`
  (`data` base64, `mimeType`), `toolCall` (`id`, `name`, `arguments` object,
  optional `thoughtSignature`, optional `namespace`).
- Messages: `system`, `user` (string or text/image blocks), `assistant`
  (text/thinking/toolCall blocks + `api`, `provider`, `model`, `usage`,
  `stopReason`, optional `responseId`, `responseModel`, `errorMessage`,
  `rawStopReason`), `toolResult` (`toolCallId`, `toolName`, text/image blocks,
  `isError`, optional `details`).
- The "signature" fields are opaque replay data and mean different things per
  API:

| API | `thinkingSignature` holds | `textSignature` holds | `toolCall.thoughtSignature` |
|---|---|---|---|
| anthropic-messages | the `signature` of the thinking block; for `redacted: true` the opaque `data` of `redacted_thinking` | - | - |
| openai-responses / codex / azure | the **whole reasoning output item as JSON** (id, summary, `encrypted_content`) | JSON `{"v":1,"id":"msg_...","phase":"commentary"|"final_answer"}` | - |
| openai-completions | name of the field the reasoning arrived in (`reasoning_content`, `reasoning`, `reasoning_text`) or a JSON array of OpenRouter `reasoning_details` | - | legacy encrypted reasoning detail |
| google-generative-ai / vertex | Gemini `thoughtSignature` (base64) | Gemini `thoughtSignature` attached to a text part | Gemini `thoughtSignature` attached to the functionCall part |

  Evidence: `anthropic-messages.ts:642-660, 713-719`;
  `openai-responses-shared.ts:53-57, 689-711`; `openai-completions.ts:606-633,
  665-676`; `google-generative-ai.ts:148-165, 203-209`.
- Tool call ids from the Responses API are stored as `"{call_id}|{item_id}"`
  (`openai-responses-shared.ts:490`), which is why hand-off needs id
  normalisation.

### 2.3 Normalised streaming event protocol

Verbatim definition in section 3.2. Rules (VERIFIED, `types.ts:752-783`,
`packages/ai/README.md:701-724`):

- Success: `start` -> updates -> `done`. Failure after generation started:
  `start` -> updates -> `error`. Failure during request setup: only `error`.
  One exception documented in the same comment: direct `streamSimple()` calls
  throw synchronously when request auth is missing (`assertRequestAuth`,
  before any stream object exists).
- `partial` on every non-terminal event is the **live, shared, mutable**
  message, not a snapshot.
- Events of different blocks may interleave; consumers must route by
  `contentIndex`.
- `toolcall_end.toolCall.arguments` is parsed but **not schema-validated**;
  validation is the caller's job (`validateToolCall`).
- Google does not stream function-call arguments: one `toolcall_start`, one
  `toolcall_delta` with the full JSON, one `toolcall_end`
  (`google-generative-ai.ts:211-219`).
- OpenAI chat completions has no per-block end marker, so all `*_end` events
  are emitted after the stream finishes, in block order
  (`openai-completions.ts:680-682`). (Confirmed in the prototype output,
  section 5.3.)

### 2.4 Provider table (every built-in provider)

Sources: provider factories `packages/ai/src/providers/*.ts`, env map
`packages/ai/src/env-api-keys.ts:68-122`, and the live catalog
`https://pi.dev/api/models/providers/{id}?types=chat,image,classifier`
(executed `provider_table.R` on 2026-09-29; model counts are from that run).
All rows VERIFIED unless noted. "OAuth" = provider has an `oauth` auth method.

| Provider id | Wire format(s) (`model.api`) | Base URL | Auth env var(s) | OAuth | Models | Notable quirks / compat flags |
|---|---|---|---|---|---|---|
| `anthropic` | anthropic-messages | `https://api.anthropic.com` | `ANTHROPIC_API_KEY`; `ANTHROPIC_OAUTH_TOKEN` (used as api key); `ANTHROPIC_AUTH_TOKEN` (sent as `Authorization: Bearer`) | yes (Claude Pro/Max) | 16 | adaptive vs budget thinking (`forceAdaptiveThinking` on 10), `supportsTemperature:false` on Opus 4.7, 4.8, 5, 5.5 and Sonnet 5.5 (verifier, live catalog), mid-conversation system messages/effort/tool changes, `cache_control`, strict tools |
| `openai` | openai-responses | `https://api.openai.com/v1` | `OPENAI_API_KEY` | yes (Sign in with ChatGPT) | 44 | `store:false` always; `reasoning.encrypted_content` replay; context-tier pricing above 272k tokens; ChatGPT tokens (non `sk-` keys) must omit `max_output_tokens`, `temperature`, cache options |
| `openai-codex` | openai-codex-responses | `https://chatgpt.com/backend-api` (request goes to `/codex/responses`) | none | yes (Codex client, "legacy") | 9 | `chatgpt-account-id` header from JWT, `originator`, `OpenAI-Beta: responses=experimental`, optional zstd body, WebSocket transport with `previous_response_id` |
| `google` | google-generative-ai | `https://generativelanguage.googleapis.com/v1beta` | `GEMINI_API_KEY` | no | 22 | `thinkingLevel` (Gemini 3.x) vs `thinkingBudget` (2.5); `thoughtSignature` replay; no streamed tool args; function responses of one turn in one user content |
| `google-vertex` | google-vertex | `https://{location}-aiplatform.googleapis.com` | `GOOGLE_CLOUD_API_KEY` or ADC (`GOOGLE_APPLICATION_CREDENTIALS` / `~/.config/gcloud/application_default_credentials.json`) + `GOOGLE_CLOUD_PROJECT`/`GCLOUD_PROJECT` + `GOOGLE_CLOUD_LOCATION` | no | 14 | Google SDK auth |
| `amazon-bedrock` | bedrock-converse-stream | `https://bedrock-runtime.us-east-1.amazonaws.com` (`eu.*` ids: `eu-central-1`) | `AWS_PROFILE`, or `AWS_ACCESS_KEY_ID`+`AWS_SECRET_ACCESS_KEY`, or `AWS_BEARER_TOKEN_BEDROCK`, ECS/IRSA vars; `AWS_REGION` | no | 176 | SigV4 + AWS binary event-stream framing (not SSE) |
| `azure-openai-responses` | azure-openai-responses | from `AZURE_OPENAI_BASE_URL` or `https://{AZURE_OPENAI_RESOURCE_NAME}.openai.azure.com/openai/v1` | `AZURE_OPENAI_API_KEY` (+ `AZURE_OPENAI_API_VERSION` default `v1`, `AZURE_OPENAI_DEPLOYMENT_NAME_MAP`) | no | 44 | deployment name = model id unless mapped; reasoning signature can arrive only in `response.completed` |
| `github-copilot` | openai-responses (18), anthropic-messages (10), openai-completions (6) | `https://api.individual.githubcopilot.com`; real base URL derived from the token's `proxy-ep` field; enterprise `https://copilot-api.{domain}` | `COPILOT_GITHUB_TOKEN` | yes (device code) | 34 | static model headers `User-Agent: GitHubCopilotChat/0.35.0`, `Editor-Version`, `Editor-Plugin-Version`, `Copilot-Integration-Id`; dynamic `X-Initiator`, `Openai-Intent: conversation-edits`, `Copilot-Vision-Request`; Bearer auth even for Anthropic format; per-account model enablement |
| `openrouter` | openai-completions (383, base `https://openrouter.ai/api/v1`), anthropic-messages (15, base `https://openrouter.ai/api`), openrouter-images (57), typesafe-system-one (7) | see left | `OPENROUTER_API_KEY` | yes (PKCE -> API key) | 462 | `thinkingFormat: openrouter` (`reasoning:{effort}`), `reasoning_details` replay, `x-session-id`, `provider` routing object, Anthropic-style `cache_control` for `anthropic/*` ids, attribution headers `HTTP-Referer`, `X-OpenRouter-Title` |
| `groq` | openai-completions | `https://api.groq.com/openai/v1` | `GROQ_API_KEY` | no | 7 | standard |
| `cerebras` | openai-completions | `https://api.cerebras.ai/v1` | `CEREBRAS_API_KEY` | no | 2 | no `store`, no `developer` role; body-less 400/413 means context overflow |
| `xai` | openai-responses | `https://api.x.ai/v1` | `XAI_API_KEY` | yes (device code) | 4 | always `include: ["reasoning.encrypted_content"]`; no `none`/`minimal` effort unless verified |
| `deepseek` | openai-completions | `https://api.deepseek.com` | `DEEPSEEK_API_KEY` | no | 2 | `thinkingFormat: deepseek` (`thinking:{type}`), `max_tokens`, requires `reasoning_content` on every replayed assistant message, cache hits in `prompt_cache_hit_tokens` |
| `mistral` | mistral-conversations | `https://api.mistral.ai` (POST `/v1/chat/completions`) | `MISTRAL_API_KEY` | no | 32 | tool call ids must be exactly 9 alphanumerics; `reasoning_effort` or `prompt_mode: "reasoning"` |
| `together` | openai-completions | `https://api.together.ai/v1` | `TOGETHER_API_KEY` | no | 20 | `thinkingFormat: together` (`reasoning:{enabled}`), `max_tokens` |
| `fireworks` | anthropic-messages (14, base `https://api.fireworks.ai/inference`), openai-completions (8, base `.../inference/v1`) | see left | `FIREWORKS_API_KEY` | no | 22 | `x-session-affinity` header, no `cache_control` on tools, no `eager_input_streaming` (legacy fine-grained beta header), `allowEmptySignature` |
| `huggingface` | openai-completions | `https://router.huggingface.co/v1` | `HF_TOKEN` | no | 76 | no `developer` role |
| `nvidia` | openai-completions | `https://integrate.api.nvidia.com/v1` | `NVIDIA_API_KEY` | no | 19 | model header `NVCF-POLL-SECONDS`; `max_tokens`; no store/developer role/reasoning_effort |
| `baseten` | openai-completions | `https://inference.baseten.co/v1` | `BASETEN_API_KEY` | no | 21 | `thinkingFormat: baseten` (`chat_template_args`), session affinity headers |
| `zai` | openai-completions | `https://api.z.ai/api/coding/paas/v4` | `ZAI_API_KEY` | no | 7 | `thinkingFormat: zai`, `tool_stream: true`, silent overflow |
| `zai-coding-cn` | openai-completions | `https://open.bigmodel.cn/api/coding/paas/v4` | `ZAI_CODING_CN_API_KEY` | no | 4 | as `zai` |
| `moonshotai` | openai-completions | `https://api.moonshot.ai/v1` | `MOONSHOT_API_KEY` | no | 4 | usage arrives in `choices[0].usage`; tool additions via `{"role":"system","tools":[...]}` |
| `moonshotai-cn` | openai-completions | `https://api.moonshot.cn/v1` | `MOONSHOT_API_KEY` | no | 4 | as above |
| `kimi-coding` | anthropic-messages | `https://api.kimi.com/coding` | `KIMI_API_KEY` | yes (device code) | 4 | OAuth token is sent as `Authorization: Bearer` header, not x-api-key |
| `minimax` | anthropic-messages | `https://api.minimax.io/anthropic` | `MINIMAX_API_KEY` | no | 3 | - |
| `minimax-cn` | anthropic-messages | `https://api.minimaxi.com/anthropic` | `MINIMAX_CN_API_KEY` | no | 3 | - |
| `meta` | openai-responses | `https://api.meta.ai/v1` | `META_API_KEY` | yes (device code + key mint) | 5 | minted key lives ~24 h |
| `ant-ling` | openai-completions | `https://api.ant-ling.com/v1` | `ANT_LING_API_KEY` | no | 3 | `thinkingFormat: ant-ling` |
| `qwen-token-plan` | openai-completions | `https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1` | `QWEN_TOKEN_PLAN_API_KEY` | no | 20 | `thinkingFormat: qwen` (`enable_thinking`) |
| `qwen-token-plan-individual` | openai-completions | same as above | `QWEN_TOKEN_PLAN_API_KEY` | no | 9 | subset catalog |
| `qwen-token-plan-cn` | openai-completions | `https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1` | `QWEN_TOKEN_PLAN_CN_API_KEY` | no | 20 | as above |
| `xiaomi` | openai-completions | `https://api.xiaomimimo.com/v1` | `XIAOMI_API_KEY` | no | 6 | `thinkingFormat: deepseek`; truncates oversized input silently |
| `xiaomi-token-plan-cn` / `-ams` / `-sgp` | openai-completions | `https://token-plan-cn.xiaomimimo.com/v1`, `https://token-plan-ams.xiaomimimo.com/v1`, `https://token-plan-sgp.xiaomimimo.com/v1` | `XIAOMI_TOKEN_PLAN_CN_API_KEY`, `..._AMS_API_KEY`, `..._SGP_API_KEY` | no | 4 each | as `xiaomi` |
| `opencode` | openai-responses (29), openai-completions (24), google-generative-ai (7) at `https://opencode.ai/zen/v1`; anthropic-messages (17) at `https://opencode.ai/zen`; typesafe-system-one (2) | see left | `OPENCODE_API_KEY` | no | 79 | `x-opencode-session`, `x-opencode-client` headers |
| `opencode-go` | openai-completions (21), openai-responses (6) at `https://opencode.ai/zen/go/v1`; anthropic-messages (2) at `https://opencode.ai/zen/go` | see left | `OPENCODE_API_KEY` | no | 29 | subscription limits return 429 `GoUsageLimitError` (not retryable) |
| `vercel-ai-gateway` | anthropic-messages (252) at `https://ai-gateway.vercel.sh`; typesafe-system-one (1) at `https://ai-gateway.vercel.sh/typesafe/v1` | see left | `AI_GATEWAY_API_KEY` | no | 253 | `allowEmptySignature`; `providerOptions.gateway` routing |
| `cloudflare-workers-ai` | openai-completions (18) at `https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/v1`; cloudflare-workers-ai-system-one (1) at `.../ai` (POST `run`) | see left | `CLOUDFLARE_API_KEY` + `CLOUDFLARE_ACCOUNT_ID` | no | 19 | URL placeholders filled from provider env |
| `cloudflare-ai-gateway` | openai-responses (24, `.../openai`), openai-completions (18, `.../compat`), anthropic-messages (12, `.../anthropic`) under `https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}` | see left | `CLOUDFLARE_API_KEY` + `CLOUDFLARE_ACCOUNT_ID` + `CLOUDFLARE_GATEWAY_ID` | no | 54 | key sent as `cf-aig-authorization: Bearer ...`; `Authorization` and `x-api-key` suppressed |
| `radius` | pi-messages | `https://radius.pi.dev/v1` | `RADIUS_API_KEY` | yes | 28 | Pi's own gateway protocol: POST `{model, context, options}` to `<baseUrl>/messages`, response is SSE of already-normalised events |
| `typesafe` | typesafe-system-one (classifier) | `https://api.typesafe.ai/v1/` | `TYPESAFE_API_KEY` | no | 1 (`jev-latest`) | System 1 / Jev, see 2.14 |

Path conventions per wire format (VERIFIED from SDK usage in source and the
hand-written Mistral/Codex clients; the Gemini REST path VERIFIED at
https://ai.google.dev/api/generate-content):

| Wire format | Request | Auth header |
|---|---|---|
| anthropic-messages | `POST {baseUrl}/v1/messages` | `x-api-key: <key>` (+ `anthropic-version: 2023-06-01`); OAuth/Bearer providers use `Authorization: Bearer <token>` |
| openai-completions | `POST {baseUrl}/chat/completions` | `Authorization: Bearer <key>` |
| openai-responses | `POST {baseUrl}/responses` | `Authorization: Bearer <key>` |
| openai-codex-responses | `POST {baseUrl}/codex/responses` | `Authorization: Bearer <access token>` + `chatgpt-account-id` |
| google-generative-ai | `POST {baseUrl}/models/{model}:streamGenerateContent?alt=sse` | `x-goog-api-key: <key>` |
| mistral-conversations | `POST {baseUrl}/v1/chat/completions` | `Authorization: Bearer <key>` |
| typesafe-system-one | `POST {baseUrl}/systemone` | `Authorization: Bearer <key>` |

### 2.5 Wire-format adapters, in detail

#### 2.5.1 anthropic-messages (`packages/ai/src/api/anthropic-messages.ts`)

Request construction (`buildParams`, lines 1043-1213) - VERIFIED:

- `model`, `messages`, `max_tokens` (request option, else `model.maxTokens`),
  `stream: true`, optional `betas`.
- `system` is an **array of text blocks**, each with
  `cache_control: {"type":"ephemeral"}` (`+ "ttl":"1h"` for
  `cacheRetention: "long"` when `supportsLongCacheRetention`).
- `tools[]`: `{name, description, eager_input_streaming: true, input_schema:
  {type:"object", properties, required}}`; `strict: true` plus the whole strict
  schema when strict sampling applies; `cache_control` on the **last** tool.
  When the provider lacks eager streaming the legacy beta header
  `fine-grained-tool-streaming-2025-05-14` is sent instead (lines 181, 1458-1463).
- Cache breakpoint on the last block of the last user message (lines 1407-1433).
- Thinking (lines 1159-1190): adaptive models get
  `thinking: {type:"adaptive", display:"summarized"}` and
  `output_config: {effort}`; budget models get
  `thinking: {type:"enabled", budget_tokens, display:"summarized"}`; explicit
  off sends `thinking: {type:"disabled"}` unless `thinkingLevelMap.off === null`.
  Pi defaults `display` to `"summarized"` because the API default on Opus 4.7+
  is `"omitted"` (empty thinking text).
- `temperature` only when thinking is not enabled and the model supports it
  (lines 1112-1120).
- `tool_choice`: string -> `{type: <string>}`; object passes through.
- `metadata.user_id` when provided.
- Beta headers (lines 181-186, 999-1041): `interleaved-thinking-2025-05-14`
  (budget-thinking models only), `server-side-fallback-2026-07-01`,
  `mid-conversation-output-config-2026-07-01`,
  `thinking-binding-controls-2026-08-01`,
  `mid-conversation-tool-changes-2026-07-01`; a caller-supplied
  `anthropic-beta` header replaces the computed list; `null` disables it.
- Client headers (lines 978-986): `accept: application/json`,
  `anthropic-dangerous-direct-browser-access: true`, `User-Agent: pi (<platform>
  <release>; <arch>)`, optional `x-session-affinity` / `x-session-id`.

Message conversion (`convertMessages`, lines 1234-1436) - VERIFIED:

- User string content is sent as a string; block content as `text` / `image`
  (`source: {type:"base64", media_type, data}`); whitespace-only text dropped.
- Assistant: `text`; `thinking` with `signature`; `redacted_thinking` with
  `data`; unsigned thinking (for example from an aborted stream) is converted
  to a `text` block (or kept with `signature: ""` when `allowEmptySignature`);
  `tool_use` with `id`, `name`, `input`.
- **All consecutive `toolResult` messages are merged into one `user` message**
  of `tool_result` blocks (`tool_use_id`, `content`, `is_error`). Image-only
  results get a `"(see attached image)"` text block in front.
- Tool call ids are normalised with
  `id.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64)` (lines 1215-1218).

Stream handling (lines 470-509, 601-797) - VERIFIED:

- Only events named `message_start`, `message_delta`, `message_stop`,
  `content_block_start`, `content_block_delta`, `content_block_stop` are
  processed; `ping` and unknown events are ignored; `event: error` throws with
  the data as message.
- Usage is read at `message_start` (input, cache read/write, 1h cache split)
  and overwritten field-by-field at `message_delta` only for non-null fields;
  `totalTokens = input + output + cacheRead + cacheWrite` (Anthropic sends no
  total); `usage.reasoning` from `output_tokens_details.thinking_tokens`.
- Block index mapping: the wire `index` is stored on the block during
  streaming and deleted at `content_block_stop`.
- The stream is invalid if `message_start` was seen but `message_stop` was not
  ("Anthropic stream ended before message_stop"), or no stop reason arrived.
- Stop reasons (lines 1502-1528): `end_turn`, `pause_turn`, `stop_sequence` ->
  `stop`; `max_tokens` -> `length`; `tool_use` -> `toolUse`; `refusal` ->
  `error` with `stop_details.explanation`; `sensitive` -> `error`.

#### 2.5.2 openai-completions (`packages/ai/src/api/openai-completions.ts`)

Request (`buildParams`, lines 797-1002) - VERIFIED:

- `model`, `messages`, `stream: true`,
  `stream_options: {include_usage: true}` (unless
  `supportsUsageInStreaming: false`), `store: false` (only if `supportsStore`),
  `max_completion_tokens` or `max_tokens` per `maxTokensField`,
  `temperature`, `tools`, `tool_choice`, `prompt_cache_key` /
  `prompt_cache_retention: "24h"`.
- If there are no tools but the history contains tool calls, `tools: []` is
  sent (needed by Anthropic behind LiteLLM-style proxies, lines 855-858).
- Reasoning parameter by `compat.thinkingFormat` (lines 875-972):

| thinkingFormat | On | Off |
|---|---|---|
| `openai` (default) | `reasoning_effort: <mapped level>` (only if `supportsReasoningEffort`) | `reasoning_effort: <thinkingLevelMap.off>` only if that is a string |
| `openrouter` | `reasoning: {effort}` | `reasoning: {effort: map.off ?? "none"}` unless `map.off === null` |
| `deepseek` | `thinking: {type:"enabled"}` (+ `reasoning_effort` if supported) | `thinking: {type:"disabled"}` unless `map.off === null` |
| `zai` | `thinking: {type:"enabled", clear_thinking:false}` | `thinking: {type:"disabled"}` |
| `qwen` | `enable_thinking: true` | `enable_thinking: false` |
| `qwen-chat-template` | `chat_template_kwargs: {enable_thinking:true, preserve_thinking:true}` | same with `false` |
| `chat-template` | `chat_template_kwargs` built from `compat.chatTemplateKwargs` with `$var` substitution (`thinking.enabled`, `thinking.effort`, `thinking.budget`) | same |
| `baseten` | `chat_template_args` + optional `reasoning_effort` | same |
| `together` | `reasoning: {enabled:true}` (+ `reasoning_effort`) | `reasoning: {enabled:false}` |
| `string-thinking` | `thinking: "<level>"` | `thinking: map.off ?? "none"` |
| `ant-ling` | `reasoning: {effort}` only when mapped | nothing |

- Optional top-level token budget field for self-hosted servers
  (`thinking_token_budget` vLLM, `thinking_budget` Qwen/SGLang,
  `thinking_budget_tokens` llama.cpp), clamped so at least 1024 answer tokens
  remain.
- `model.samplingParams` and `options.samplingParams` are merged last and
  override named fields.

Compat auto-detection from provider id / base URL (`detectCompat`, lines
1585-1682; verbatim in section 3.6) - VERIFIED. Explicit `model.compat` wins
per field.

Message conversion (lines 1185-1472) - VERIFIED:

- System prompt role is `developer` when the model reasons and the endpoint
  supports it, else `system`.
- Images: `{"type":"image_url","image_url":{"url":"data:<mime>;base64,<data>"}}`.
- Assistant `content` is always a **plain string** (joined text blocks), never
  an array - the comment at lines 1322-1326 explains that some models mimic
  the array structure otherwise. `null` content when there are only tool calls
  (or `""` when `requiresAssistantAfterToolResult`).
- Thinking replay: either as text (`requiresThinkingAsText`), or written back
  into the field named by the signature (`reasoning_content`, ...), or as
  `reasoning_details`.
- Tool results: one `role: "tool"` message each (`tool_call_id`, text
  content; `"(see attached image)"` / `"(no tool output)"` placeholders);
  images of tool results are collected into one following `user` message
  `"Attached image(s) from tool result:"`.
- Tool call id normalisation (lines 1194-1218): ids containing `|` become
  `"{call}_{item}"` sanitised to `[a-zA-Z0-9_-]`, max 40 chars with an 8 char
  hash suffix when longer; plain ids are truncated to 40 only for provider
  `openai`.

Stream handling (lines 553-701) - VERIFIED:

- `choices[0].delta.content` -> text; first non-empty of `reasoning_content`,
  `reasoning`, `reasoning_text` -> thinking (only one field is used to avoid
  duplicates); `delta.tool_calls[]` matched by `index`, then by `id`.
- Usage from the final `usage` chunk (or `choices[0].usage` for Moonshot);
  `input = prompt_tokens - cached - cache_write`.
- Stop reasons (lines 1554-1578): `stop`/`end` -> `stop`; `length`;
  `tool_calls`/`function_call` -> `toolUse`; `content_filter`,
  `network_error`, anything else -> `error`.
- Missing `finish_reason` is an error unless `supportsFinishReason: false`.

#### 2.5.3 openai-responses (`openai-responses.ts`, `openai-responses-shared.ts`)

Request (`openai-responses.ts:302-385`) - VERIFIED: `model`, `input`,
`stream: true`, `store: false`, `prompt_cache_key` (session id clamped to 64
chars), `prompt_cache_retention: "24h"` or `prompt_cache_options`,
`max_output_tokens` (minimum 16), `temperature`, `service_tier`, `tools`,
`tool_choice`, `reasoning: {effort, summary: "auto"}` +
`include: ["reasoning.encrypted_content"]`; when reasoning is off:
`reasoning: {effort: map.off ?? "none"}` unless `map.off === null` or the
provider is GitHub Copilot.

Input items (`convertResponsesMessages`, shared lines 145-355) - VERIFIED:

- System: `{role: "developer"|"system", content}`.
- User: `{role:"user", content:[{type:"input_text"}|{type:"input_image",
  detail:"auto", image_url:"data:..."}]}`.
- Assistant thinking: the stored reasoning item JSON is pushed back verbatim.
- Assistant text: `{type:"message", role:"assistant", status:"completed", id,
  phase?, content:[{type:"output_text", text, annotations:[]}]}`; id from the
  text signature, else `msg_pi_<n>`; ids above 64 chars are hashed.
- Tool call: `{type:"function_call", id?, call_id, name, arguments:<JSON
  string>}`; the item id is omitted when the message came from a different
  model or does not start with `fc_`.
- Tool result: `{type:"function_call_output", call_id, output}` where `output`
  is a string or an array of `input_text`/`input_image`.

Stream events handled (`processResponsesStream`, shared lines 434-778) -
VERIFIED: `response.created`, `response.output_item.added`,
`response.reasoning_summary_text.delta`, `response.reasoning_summary_part.done`
(appends `"\n\n"`), `response.reasoning_text.delta`,
`response.output_text.delta`, `response.refusal.delta`,
`response.function_call_arguments.delta|done`,
`response.custom_tool_call_input.delta|done`, `response.output_item.done`,
`response.completed`, `response.incomplete`, `response.failed`, `error`.
A stream without a terminal response event is an error; a `toolUse` result
with a tool call whose `output_item.done` never arrived is an error.
Status mapping (lines 780-810): `completed` -> `stop` (-> `toolUse` if the
message contains tool calls); `incomplete` with reason `max_output_tokens` ->
`length`, other reasons -> `error`; `failed`/`cancelled` -> `error`.
Service tier price multipliers: `flex` 0.5, `priority`/`fast` 2 (2.5 for
`gpt-5.5`) (`openai-responses.ts:387-415`).

#### 2.5.4 openai-codex-responses (`openai-codex-responses.ts`)

VERIFIED: body (lines 553-599) `model`, `store:false`, `stream:true`,
`instructions` (system prompt, default `"You are a helpful assistant."`),
`input` (no system message), `text: {verbosity: "low"}`,
`include: ["reasoning.encrypted_content"]`, `prompt_cache_key`,
`tool_choice: "auto"`, `parallel_tool_calls: true`, optional `reasoning`.
Headers (lines 1640-1697) `Authorization: Bearer`, `chatgpt-account-id`,
`originator: pi`, `User-Agent`, `OpenAI-Beta: responses=experimental`,
`accept: text/event-stream`, `session-id`, `x-client-request-id`; request body
may be zstd compressed (`content-encoding: zstd`). Events `response.done`
and `response.incomplete` are rewritten to `response.completed`
(lines 774-783). Retry on 429/5xx with `retry-after-ms`/`retry-after`,
except terminal quota errors (lines 123-137). Friendly usage-limit message
built from `error.plan_type` and `error.resets_at` (lines 1596-1621).
WebSocket transport is optional and falls back to SSE.

#### 2.5.5 google-generative-ai (`google-generative-ai.ts`, `google-shared.ts`)

VERIFIED: `contents[]` with roles `user`/`model`; `systemInstruction`;
`tools: [{functionDeclarations:[{name, description, parametersJsonSchema}]}]`;
`toolConfig.functionCallingConfig.mode` (`AUTO|NONE|ANY|VALIDATED`);
`generationConfig.temperature`, `maxOutputTokens`,
`thinkingConfig: {includeThoughts:true, thinkingLevel | thinkingBudget}`.
Function calls carry `id` only for models that need it (Gemini >= 3, `claude-*`,
`gpt-oss-*`; `google-shared.ts:165-172`). Function responses use
`{output: <text>}` or `{error: <text>}`; images go inside
`functionResponse.parts` for Gemini >= 3, else into a separate user turn.
Thought signatures are replayed only for the same provider + model and only if
they are valid base64 (`google-shared.ts:146-160`). Usage:
`input = promptTokenCount - cachedContentTokenCount`,
`output = candidatesTokenCount + thoughtsTokenCount`. Finish reasons: `STOP` ->
`stop` (-> `toolUse` with tool calls), `MAX_TOKENS` -> `length`, everything
else -> `error`.

UNCERTAIN: on 2026-09-29 Google's "thinking" documentation page
(https://ai.google.dev/gemini-api/docs/thinking) presented a newer request
shape (`input`, `generation_config.thinking_summaries`, snake_case
`thinking_level`), which suggests a newer "Interactions"-style API exists next
to `generateContent`. (Verifier: confirmed that it exists - the Gemini API-key
page https://ai.google.dev/gemini-api/docs/api-key now shows
`POST https://generativelanguage.googleapis.com/v1beta/interactions` with
header `x-goog-api-key` and body `{model, input}` as its REST example.) The
`streamGenerateContent` reference page still documents the shape above (its
own curl example passes the key as `?key=`; the `x-goog-api-key` header is
documented on the API-key page). gptr should target `streamGenerateContent`
and re-check before release.

### 2.6 Thinking / reasoning levels per provider

Unified levels and clamping (VERIFIED, `models.ts:1215-1247`, verbatim in
section 3.4):

- Order: `off, minimal, low, medium, high, xhigh, max`.
- A level is supported when the model reasons and `thinkingLevelMap[level]` is
  not `null`; `xhigh` and `max` are opt-in (must be present in the map).
- Clamping searches **upwards first**, then downwards.

| API | Mapping of a unified level (after clamping) | Source |
|---|---|---|
| anthropic-messages, adaptive model (`compat.forceAdaptiveThinking`) | `thinking:{type:"adaptive"}` + `output_config.effort = thinkingLevelMap[level]`, else `minimal,low -> "low"`, `medium -> "medium"`, otherwise `"high"` | `anthropic-messages.ts:846-892` |
| anthropic-messages, budget model | `budget = DEFAULT_THINKING_BUDGETS[level]` (xhigh/max -> high); `max_tokens = min(requested + budget, model.maxTokens)` (model cap if none requested), then clamped to the context window (`clampMaxTokensToContext`: `min(max_tokens, contextWindow - estimate - 4096)`, at least 1); `budget_tokens = min(budget, max(0, max_tokens - 1024))` on the clamped value; beta `interleaved-thinking-2025-05-14` | `anthropic-messages.ts:895-911`, `simple-options.ts:54-92` |
| anthropic-messages, off | `thinking:{type:"disabled"}` unless `map.off === null` (always-thinking models such as Opus 5.5, Fable) | `anthropic-messages.ts:1187-1189` |
| openai-responses / azure | `reasoning.effort = map[level] ?? level`, `summary:"auto"`; off -> `map.off ?? "none"` unless `null` | `openai-responses.ts:363-379` |
| openai-codex-responses | same; generator maps `minimal -> "low"` for xhigh-capable models | `openai-codex-responses.ts:582-597`, `scripts/generate-models.ts:1132-1134` |
| openai-completions | per `thinkingFormat`, table in 2.5.2 | `openai-completions.ts:875-972` |
| google-generative-ai (Gemini 3.x, `gemini-flash-latest`, Gemma 4) | `thinkingLevel: MINIMAL|LOW|MEDIUM|HIGH`; off -> lowest supported level because thinking cannot be disabled | `google-shared.ts:72-111` |
| google-generative-ai (Gemini 2.5) | `thinkingBudget`: 2.5-pro 128/2048/8192/32768, 2.5-flash 128/2048/8192/24576, 2.5-flash-lite 512/2048/8192/24576 (minimal/low/medium/high); other models `-1` (dynamic); off -> `0` | `google-generative-ai.ts:431-471` |
| mistral-conversations | `reasoning_effort = map[level] ?? "high"` when the model has a map, else `prompt_mode: "reasoning"` | `mistral-conversations.ts:200-214` |
| bedrock-converse-stream | adaptive or budget like Anthropic | `bedrock-converse-stream.ts:547-576, 752-796` |

Catalog-side rules that produce `thinkingLevelMap` (VERIFIED,
`scripts/generate-models.ts:1028-1206`, `scripts/models-dev-reasoning-options.ts`):
models.dev `reasoning_options` of type `effort` become a full map
(`off: "none"` only if `none` is listed; unlisted levels `null`); then
hand-written corrections, for example: all `gpt-5*` Responses models
`off: null`; `gpt-5.5` `minimal: null`; Opus 4.6/Sonnet 4.6 `max`;
Opus 4.7+/Sonnet 5 `xhigh` and `max`; Fable 5 `off: null`. Live examples
(fetched 2026-09-29):

```json
{"id":"claude-opus-5-5","thinkingLevelMap":{"off":null,"minimal":null,"low":"low","medium":"medium","high":"high","xhigh":"xhigh","max":"max"}}
{"id":"gpt-5.5","thinkingLevelMap":{"off":"none","minimal":null,"low":"low","medium":"medium","high":"high","xhigh":"xhigh","max":null}}
{"id":"gemini-3-flash-preview","thinkingLevelMap":{"off":null,"minimal":"minimal","low":"low","medium":"medium","high":"high","xhigh":null,"max":null}}
```

Cross-check against Anthropic's own documentation (Claude API reference
bundled with Claude Code, cached 2026-09-25): effort values
`low|medium|high|xhigh|max` live in `output_config.effort`;
`budget_tokens` is rejected (HTTP 400) on Opus 4.7 and later, Sonnet 5 and
later, Fable 5; `thinking:{type:"disabled"}` is rejected on Opus 5.5, Sonnet
5.5 and Fable; Opus 5.5's default effort is `medium`; thinking display
defaults to `"omitted"` on those models. This matches Pi's flags
(`forceAdaptiveThinking`, `off: null`, explicit `display: "summarized"`).
VERIFIED for the documentation text; NOT verified against the live API (no
paid calls were allowed).

### 2.7 Cost computation

VERIFIED (`models.ts:1193-1213`, verbatim in section 3.4):

1. `inputTokens = usage.input + usage.cacheRead + usage.cacheWrite`.
2. Pick rates: base `model.cost`, or the tier with the highest
   `inputTokensAbove` that is below `inputTokens` (the tier applies to the
   whole request).
3. `cost.input = rates.input / 1e6 * usage.input`, same for `output` and
   `cacheRead`.
4. `cost.cacheWrite = (rates.cacheWrite * shortWrite + rates.input * 2 *
   longWrite) / 1e6` where `longWrite = usage.cacheWrite1h` (Anthropic 1 hour
   cache writes) and `shortWrite = cacheWrite - longWrite`.
5. `cost.total` = sum.

Usage normalisation differs by API: Anthropic reports input without cached
tokens; OpenAI (both APIs) includes cached tokens in the prompt/input count so
Pi subtracts them; Google subtracts `cachedContentTokenCount` and adds
`thoughtsTokenCount` to output. `usage.reasoning` is always a subset of
`output`. Subscription providers report zero cost in models.dev; Pi overrides
some (Kimi) by hand (`generate-models.ts:340`).

### 2.8 Partial JSON parsing of tool-call arguments

VERIFIED (`utils/json-parse.ts`, verbatim in section 3.5):

- `repairJson()` walks the text, and inside string literals escapes raw
  control characters (`\n`, `\t`, `\u00XX`) and doubles backslashes that start
  an invalid escape (keeps valid `\uXXXX`).
- `parseStreamingJson(partial)`: empty -> `{}`; strict parse (with repair);
  else `partial-json` parse; else `partial-json` parse of the repaired text;
  else `{}`. The result is never `undefined`.
- Where it is called: on every `input_json_delta` (Anthropic), every
  `function.arguments` delta (chat completions), every
  `response.function_call_arguments.delta` (Responses), and once more at block
  end. The scratch fields (`partialJson`, `partialArgs`, `streamIndex`,
  `index`) are deleted before the message is returned or persisted.
- `partial-json` semantics with `Allow.ALL` (VERIFIED by the verifier against
  the raw main-branch source
  https://raw.githubusercontent.com/promplate/partial-json-parser-js/main/src/index.ts;
  Pi pins npm `partial-json` 0.1.7, whose repository is that project. Pi calls
  `parse(text)` with no second argument and the library default is
  `allowPartial = Allow.ALL`):
  unterminated strings are returned truncated (a dangling backslash is cut),
  partial literals `t/tr/tru`, `f...`, `n...` are completed, incomplete
  object keys and keys without values are dropped, arrays/objects are closed,
  a trailing number is accepted if it parses (otherwise the key is dropped).
  `Allow.ALL` also accepts `Infinity`, `-Infinity`, `NaN` and their prefixes,
  which the R port does not.

Anthropic's own guidance for eager input streaming (VERIFIED, Claude API
reference `shared/tool-use-concepts.md`): without server-side buffering the
accumulated JSON can be truncated at `max_tokens` or be invalid; a client
should parse the final text strictly, validate against the tool schema, never
execute tools when `stop_reason` is `max_tokens` or `refusal`, and answer an
unparseable call with an error tool result of the form
`{"INVALID_JSON": "<raw text>"}`.

### 2.9 Cross-provider hand-off (`transformMessages`)

VERIFIED (`api/transform-messages.ts:64-235`, verbatim in section 3.5).

Pass 1 (per message):

1. `content == null` becomes `[]`.
2. If the target model has no image input, image blocks in user messages and
   tool results are replaced by one placeholder text block per run of images:
   `"(image omitted: model does not support images)"` /
   `"(tool image omitted: model does not support images)"`.
3. Assistant messages: `isSameModel = provider, api and model id all equal`.
   - Redacted thinking: kept only for the same model, otherwise dropped.
   - Thinking with a signature: kept for the same model (even if the text is
     empty).
   - Empty thinking: dropped.
   - Other thinking: kept for the same model, otherwise converted to a plain
     `text` block **without tags**. (The README at
     `packages/ai/README.md:1526` says "with `<thinking>` tags"; the code does
     not add tags - code comments say tags are avoided so models do not mimic
     them. The code is authoritative.)
   - Text: signature stripped for a different model.
   - Tool call: `thoughtSignature` removed for a different model; id passed
     through the adapter's `normalizeToolCallId(id, model, sourceMessage)`;
     changed ids are remembered.
4. Tool results: `toolCallId` rewritten through the id map.

Pass 2 (whole transcript):

1. Assistant messages with `stopReason` `error` or `aborted` are **skipped
   entirely**.
2. When the next assistant or user message arrives (or the transcript ends)
   while tool calls of the previous assistant message have no result, a
   synthetic result is inserted:
   `{role:"toolResult", toolCallId, toolName, content:[{type:"text",
   text:"No result provided"}], isError:true}`.
3. System messages that fall between a tool call and its results are held back
   and emitted after the results.

Id normalisers per target API:

| Target | Rule | Source |
|---|---|---|
| anthropic-messages | replace `[^a-zA-Z0-9_-]` by `_`, cut to 64 | `anthropic-messages.ts:1215-1218` |
| google (models needing ids) | same as Anthropic | `google-shared.ts:195-198` |
| openai-completions | `call|item` -> `call_item` sanitised, max 40, hash suffix if longer; plain ids cut to 40 for provider `openai` | `openai-completions.ts:1194-1218` |
| openai-responses / codex | keeps `call_id|item_id`; each part sanitised, max 64, trailing `_` trimmed; foreign item ids become `fc_<hash>`; item id must start with `fc_` | `openai-responses-shared.ts:154-177` |
| mistral | 9 alphanumeric chars; collisions resolved by re-hashing with an attempt counter | `mistral-conversations.ts:237-267` |

### 2.10 Model catalog: generation and run-time refresh

Build time (VERIFIED, `packages/ai/scripts/generate-models.ts`,
`packages/ai/package.json` scripts):

- `npm run generate-models` runs `scripts/generate-models.ts --strict`.
- Sources fetched: `https://models.dev/api.json` (line 1759),
  `https://models.dev/models.json?type=decision` (line 2677, classifier
  models, currently only `typesafe/jev-latest`),
  `https://openrouter.ai/api/v1/models` (line 1300),
  `https://ai-gateway.vercel.sh/v1/models` (lines 224, 1350),
  `https://integrate.api.nvidia.com/v1/models` (line 1280), the Radius gateway
  config (`/v1/config`).
- Only models with `tool_call === true` are kept (for example line 1811).
- Per model: `reasoning`, `input` (`["text","image"]` if models.dev lists image
  input), `cost` (input, output, cache_read, cache_write, context tiers),
  `contextWindow = limit.context || 4096`, `maxTokens = limit.output || 4096`.
- Then a long list of hand-maintained corrections: missing models (for example
  Claude Opus 5.5 / Sonnet 5.5 "until models.dev includes it", lines
  2770-2823), compat flags, thinking maps, pricing overrides.
- Output: one JSON file per provider under `src/providers/data/<id>.json`
  grouped by API with keys `"<type>:<id>"`, a manifest `.manifest.json`
  (`schemaVersion` 6, `generatedAt`, `structureHash`, SHA-256 per file) and
  generated TypeScript shims (`scripts/model-data.ts`).
  The data directory is not committed; it is hydrated at build.

Run time (VERIFIED, `packages/coding-agent/src/core/remote-catalog-provider.ts`):

- URL: `https://pi.dev/api/models/providers/<provider id>?types=chat,image,classifier`.
- Headers: `accept: application/json`, `User-Agent`, `if-none-match: <etag>`
  when a cached body exists.
- Refresh interval 4 hours (`REMOTE_CATALOG_REFRESH_INTERVAL_MS`), attempt
  timeout 4 s, `force` bypasses the interval (`pi update --models`).
- `304` moves only `checkedAt`; `404`/`501` stores an empty overlay; other
  failures keep the cached body and etag.
- The overlay is used only if its `Last-Modified` is newer than the bundled
  catalog's `generatedAt`.
- Persisted entry: `{models, lastModified, checkedAt, etag}`
  (`packages/ai/src/models-store.ts:3-15`).
- Merge rule: remote entries replace bundled entries with the same type + id;
  new ids are appended.
- `PI_OFFLINE` disables automatic network activity
  (`docs/environment-variables.md:84`).

Executed checks (2026-09-29):

```
models.dev/api.json            -> 200, 5,263,744 bytes, 225 providers, 8,323 models (7,275 tool capable),
                                  ETag W/"d187e60e79b97a4d0dee682138d44e1d", cache-control: public, max-age=0, must-revalidate
models.dev/models.json?type=decision -> 200, 450 bytes, one entry "typesafe/jev-latest" (context 64000)
pi.dev/api/models/providers/anthropic?types=... -> 200, 10,475 bytes, 16 models, ETag + Last-Modified present
```

models.dev entry shape (VERIFIED by fetch; one real entry):

```json
{"id":"claude-opus-5-5","name":"Claude Opus 5.5","family":"claude-opus","attachment":true,"reasoning":true,
 "reasoning_options":[{"type":"effort","values":["low","medium","high","xhigh","max"]}],
 "tool_call":true,"structured_output":true,"temperature":false,"knowledge":"2026-06",
 "release_date":"2026-09-22","last_updated":"2026-09-22",
 "modalities":{"input":["text","image","pdf"],"output":["text"]},"open_weights":false,
 "limit":{"context":1000000,"output":128000},
 "cost":{"input":4,"output":20,"cache_read":0.2,"cache_write":5},
 "canonical_model_id":"anthropic/claude-opus-5-5"}
```

Provider-level fields in models.dev: `id`, `env` (array of env var names),
`npm` (AI-SDK package name = wire-format hint), optional `api` (base URL),
`name`, `doc`, `models`. Distribution of `npm` over the 225 providers:
184 `@ai-sdk/openai-compatible`, 8 `@ai-sdk/anthropic`, 6 `@ai-sdk/openai`,
2 `@ai-sdk/azure`, 2 `@openrouter/ai-sdk-provider`, then single entries
(`@ai-sdk/google`, `@ai-sdk/groq`, `@ai-sdk/cerebras`, ...). Models can
override with `provider.npm`.

### 2.11 Auth resolution and credential storage

VERIFIED (`auth/types.ts`, `auth/resolve.ts`, `auth/helpers.ts`,
`coding-agent/src/core/auth-storage.ts`, docs):

- One credential per provider id. Two shapes:

```json
{"type": "api_key", "key": "sk-...", "env": {"CLOUDFLARE_ACCOUNT_ID": "..."}}
{"type": "oauth", "access": "...", "refresh": "...", "expires": 1759100000000, "...provider extras": "..."}
```

  `expires` is Unix **milliseconds**. Provider extras: `accountId` (Codex),
  `clientId` + `scopes` (Sign in with ChatGPT), `enterpriseUrl` +
  `availableModelIds` (Copilot), `scope` (Radius).
- File: `~/.pi/agent/auth.json` (`PI_CODING_AGENT_DIR` overrides the
  directory); created with mode `0600`, directory `0700`; pretty-printed JSON
  object keyed by provider id; BOM tolerated.
- Locking: `proper-lockfile` on the file; sync path retries 10 x 20 ms; async
  path retries with jittered exponential backoff up to 30 s; stale lock after
  30 s.
- `key` may be a command: a leading `!` runs a shell command once and caches
  stdout (`docs/providers.md:71-84`); `$NAME` / `${NAME}` interpolate
  environment variables in `models.json`.
- Resolution (`resolveProviderAuth`): (1) explicit `apiKey` override;
  (2) stored credential - OAuth goes through the locked refresh, api key through
  the provider's `resolve()`; a stored credential of a type the provider cannot
  handle yields "not configured" (no silent fallback to env); (3) ambient env.
- OAuth refresh (`resolveStoredOAuth`, lines 102-162): if
  `now + 5 min >= expires`, take the store lock, re-read, re-check, call
  `oauth.refresh()` with a 15 s timeout, persist, release. Refresh failure
  raises `ModelsError("oauth")` and leaves the stored credential untouched.
- Anthropic env precedence (`providers/anthropic.ts:18-39`): stored key ->
  `ANTHROPIC_AUTH_TOKEN` (Bearer header) -> `ANTHROPIC_OAUTH_TOKEN` ->
  `ANTHROPIC_API_KEY`.
- Login UI protocol (`AuthInteraction`): `prompt({type: "text"|"secret"|
  "select"|"manual_code", ...})` returns a string; `notify({type: "info"|
  "auth_url"|"device_code"|"progress", ...})`. UI neutral, so it maps directly
  onto R console prompts.

### 2.12 OAuth / subscription login flows in the source

Shared mechanics (VERIFIED):

- PKCE (`auth/oauth/pkce.ts`): verifier = base64url(32 random bytes), challenge
  = base64url(SHA-256(verifier)), method `S256`.
- Loopback server (`auth/oauth/callback-server.ts`): Node `http` server on
  `127.0.0.1` (override with `PI_OAUTH_CALLBACK_HOST`); only `GET <path>`;
  rejects a wrong `state` with HTTP 400 without ending the wait; second
  callback gets HTTP 409; `error`/`error_description` query parameters fail the
  login; success page "Signed in to <provider>. You may now close this page.".
- Manual fallback: the callback is raced against a `manual_code` prompt, so a
  user on a remote machine can paste the final redirect URL, `code#state`, a
  query string or the bare code.
- Device code (`auth/oauth/device-code.ts`): RFC 8628 polling, default interval
  5 s, minimum 1 s, `slow_down` uses the server's new interval or adds 5 s,
  timeout message mentions clock drift in WSL/VMs.
- Verification URLs from device responses are validated to be `http(s)` before
  being opened.

Per provider:

| Provider (file) | Flow | Authorize / device URL | Token URL | Client id | Scopes | Redirect | Refresh | Extra |
|---|---|---|---|---|---|---|---|---|
| Anthropic (`anthropic.ts`) | Auth code + PKCE | `https://claude.ai/oauth/authorize` with `code=true`, `state` = the PKCE verifier | `https://platform.claude.com/v1/oauth/token`, **JSON body** `{grant_type, client_id, code, state, redirect_uri, code_verifier}` | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (stored base64-encoded in source) | `org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload` | `http://localhost:53692/callback` (server binds 127.0.0.1:53692) | JSON `{grant_type:"refresh_token", client_id, refresh_token}`; expiry stored as `now + expires_in - 5 min` | `isSubscription: true` |
| OpenAI Sign in with ChatGPT (`openai-chatgpt.ts`) | Auth code + PKCE + nonce, dynamic client | `https://auth.openai.com/api/accounts/authorize` with `client_id=dynamic_agent_client`, `agent_name_hint=Pi`, `ext_agent_host_id=urn:uuid:<device uuid>`, `resource=https://api.openai.com/v1` | `https://auth.openai.com/api/accounts/oauth/token`, form encoded, includes `resource` | issued per installation, returned in the callback as `client_id` | `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct` | `http://127.0.0.1:1455/auth/callback` | form `{grant_type:"refresh_token", client_id, refresh_token, resource}`; expiry margin 3 min | grant must include `chatgpt.tokens.use.direct`; token is used directly against `api.openai.com` |
| OpenAI Codex legacy (`openai-codex.ts`) | Auth code + PKCE, or device code | `https://auth.openai.com/oauth/authorize` with `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, `originator=pi`; device: `POST https://auth.openai.com/api/accounts/deviceauth/usercode` (JSON `{client_id}`), user visits `https://auth.openai.com/codex/device` | `https://auth.openai.com/oauth/token`, form encoded; device poll `POST .../api/accounts/deviceauth/token` (JSON `{device_auth_id, user_code}`, 403/404 = pending) returns `{authorization_code, code_verifier}` | `app_EMoamEEZ73f0CkXaXp7hrann` | `openid profile email offline_access` | `http://localhost:1455/auth/callback` (device: `https://auth.openai.com/deviceauth/callback`) | form `{grant_type:"refresh_token", refresh_token, client_id}` | `accountId` = JWT claim `["https://api.openai.com/auth"].chatgpt_account_id`; port 1455 is shared with the Codex CLI |
| GitHub Copilot (`github-copilot.ts`) | Device code | `POST https://{domain}/login/device/code` (form `client_id`, `scope=read:user`) | `POST https://{domain}/login/oauth/access_token` with grant `urn:ietf:params:oauth:grant-type:device_code`; then `GET https://api.{domain}/copilot_internal/v2/token` with `Authorization: Bearer <github token>` | `Iv1.b507a08c87ecfe98` (stored base64-encoded) | `read:user` | none | re-calls the `copilot_internal/v2/token` endpoint with the GitHub token (stored as `refresh`); `expires = expires_at*1000 - 5 min` | editor headers `User-Agent: GitHubCopilotChat/0.35.0`, `Editor-Version: vscode/1.107.0`, `Editor-Plugin-Version: copilot-chat/0.35.0`, `Copilot-Integration-Id: vscode-chat`; `X-GitHub-Api-Version: 2026-06-01` for `/models`; model enablement `POST {base}/models/{id}/policy {"state":"enabled"}` |
| OpenRouter (`openrouter.ts`) | PKCE, no state | `https://openrouter.ai/auth?callback_url=...&code_challenge=...&code_challenge_method=S256` | `POST https://openrouter.ai/api/v1/auth/keys` JSON `{code, code_verifier, code_challenge_method:"S256"}` -> `{key}` | none | none | ephemeral port, random path `/oauth/callback/<uuid>` | none (permanent key; `expires = Number.MAX_SAFE_INTEGER`, `refresh: ""`) | login timeout 5 min, exchange timeout 30 s |
| xAI (`xai.ts`) | Device code | `POST https://auth.x.ai/oauth2/device/code` (form `client_id`, `scope`, `referrer=pi`) | `POST https://auth.x.ai/oauth2/token` | `b1a00492-073a-47ea-816f-4c329264a828` | `openid profile email offline_access grok-cli:access api:access` | none | standard refresh; keeps the old refresh token if none returned; skew 5 min | - |
| Kimi (`kimi-coding.ts`) | Device code | `POST https://auth.kimi.com/api/oauth/device_authorization` | `POST https://auth.kimi.com/api/oauth/token` | `17e5f671-d194-4dfb-9706-5516cb48c098` | none | none | refresh with up to 3 retries on 429/5xx | request auth is `Authorization: Bearer` header |
| Meta (`meta.ts`) | Device code + key mint | `POST https://auth.meta.com/oidc/device/authorization/` | `POST https://auth.meta.com/oidc/device/token/`; then `POST https://api.meta.ai/muse-code/key` (Bearer identity token, header `x-api-version: 1.0.0`, body `{}`) -> `{api_key}` | `1031625952748946` | none | none | "refresh" re-mints the key from the identity token (stored as `refresh`); key lifetime 24 h | identity token is not renewable |
| Radius (`radius.ts`) | Auth code + PKCE or device code | discovered via `GET {gateway}/v1/oauth` -> `authorizationEndpoint`; device `POST {gateway}/v1/oauth/device` | `POST {gateway}/v1/oauth/token` | `pi-gateway` | `gateway offline_access` | `http://127.0.0.1:1456/oauth/callback` | standard; skew 60 s | Pi-specific |

Request-time requirements when a subscription token is used (VERIFIED from the
adapters):

- **Anthropic OAuth token** (detected by substring `sk-ant-oat`,
  `anthropic-messages.ts:914-916`): `Authorization: Bearer <token>` instead of
  `x-api-key`; headers `user-agent: claude-cli/2.1.280`, `x-app: cli`,
  `accept: application/json`,
  `anthropic-dangerous-direct-browser-access: true` (lines 949-968); betas
  `claude-code-20250219` and `oauth-2025-04-20` prepended (line 1025); first
  system block must be exactly
  `"You are Claude Code, Anthropic's official CLI for Claude."` with the user's
  system prompt as a second block (lines 1085-1100); tool names that match
  Claude Code's tool list case-insensitively are sent in Claude Code's casing
  (`Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, EnterPlanMode,
  ExitPlanMode, KillShell, NotebookEdit, Skill, Task, TaskOutput, TodoWrite,
  WebFetch, WebSearch`) and mapped back on the way in (lines 86-123, 665-667,
  1367, 1492).
- **Sign in with ChatGPT token** (`openai-responses.ts:36-47, 328-346`): any
  key for provider `openai` on `https://api.openai.com/v1` that does not start
  with `sk-` is treated as a ChatGPT token; `max_output_tokens`,
  `temperature`, `prompt_cache_retention`, `prompt_cache_options` are omitted;
  error code `subscription_sharing_usage_limit_exceeded` gets a pointer to
  `https://chatgpt.com/settings/usage`.
- **Codex token**: see 2.5.4.
- **Copilot token**: base URL from the token; editor headers; dynamic headers.

### 2.13 Terms-of-service statements found

In Pi's code and docs (VERIFIED):

| Where | Text / meaning |
|---|---|
| `packages/ai/src/api/anthropic-messages.ts:86` | Comment: "Stealth mode: Mimic Claude Code's tool naming exactly" |
| `packages/ai/src/api/anthropic-messages.ts:1085` | Comment: "For OAuth tokens, we MUST include Claude Code identity" |
| `packages/coding-agent/src/modes/interactive/interactive-mode.ts:298-299` | Warning shown once per session: "Anthropic subscription auth is active. Third-party harness usage draws from extra usage and is billed per token, not your Claude plan limits. Manage extra usage at https://claude.ai/settings/usage. Disable this warning in /settings." |
| `packages/coding-agent/docs/settings.md:167` | Setting `warnings.anthropicExtraUsage` (default true) |
| `packages/ai/src/auth/oauth/openai-chatgpt.ts:1-6` | "This public-client flow uses no client secret and sends the resulting user access token directly to api.openai.com." |
| `packages/ai/src/providers/openai-codex.ts:10` | Provider display name "OpenAI Codex (legacy)"; README says it is "Superseded by Sign in with ChatGPT on the OpenAI provider" |
| `packages/ai/CHANGELOG.md:1025, 1046` | Google Gemini CLI and Antigravity OAuth providers were removed |

No file in `packages/ai` or `packages/coding-agent/docs` contains an explicit
terms-of-service discussion (grep for "terms of service", "ToS", "violat",
"ban", "at your own risk" returned only the lines above and unrelated hits).

Vendor policy, fetched 2026-09-29 (VERIFIED as published text):

- Anthropic, https://code.claude.com/docs/en/legal-and-compliance, section
  "Authentication and credential use": OAuth authentication "is intended
  exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise
  subscription plans and is designed to support ordinary use of Claude Code and
  other native Anthropic applications." Developers "building products or
  services that interact with Claude's capabilities, including those using the
  Agent SDK, should use API key authentication". "Anthropic does not permit
  third-party developers to offer Claude.ai login into their own applications,
  or to route requests through Free, Pro, or Max plan credentials on behalf of
  their users." Developers "may not collect, store, or intermediate Claude.ai
  credentials or session tokens". It also says this does not "prevent an end
  user from signing in to the unmodified Claude Code binary with their own
  Claude subscription", and that the binary must not be modified.
  (Verifier, raw re-fetch: every quote above is character exact.) The same
  page, section "Can customers offer Claude Code in their products?", adds:
  "preinstalling or running Claude Code in your products or services (e.g. in
  hosted sandboxes or other agent infrastructure) requires agreeing to our
  Commercial Terms of Service", the binary must not be modified, no built-in
  authentication method may be removed or restricted, and each end user must
  authenticate with their own key or plan credentials; section "Acceptable
  use" says advertised Pro/Max limits "assume ordinary, individual usage of
  Claude Code and the Agent SDK". Whether a locally installed open-source R
  package that shells out to the user's own `claude` counts as "running Claude
  Code in your products" is not stated (UNCERTAIN).
- Anthropic help centre,
  https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan:
  a planned separate monthly credit for programmatic use (Agent SDK,
  `claude -p`, GitHub Actions, third-party apps on the Agent SDK) was
  **paused on 2026-06-15**; "For now, nothing has changed: Claude Agent SDK,
  `claude -p`, and third-party app usage still draw from your subscription's
  usage limits." (Verifier: quote confirmed, article dated June 16, 2026.
  Note that Pi's own warning in the table above - third-party harness usage
  "draws from extra usage and is billed per token" - describes Pi's direct
  OAuth-token path, not `claude -p`, and was not checked against any
  Anthropic statement; do not reuse it as a fact about plan billing.)
- Press coverage of the enforcement history (LIKELY, secondary sources):
  third-party use of subscription OAuth tokens was blocked in January 2026,
  the terms were revised in February 2026 and enforced from 2026-04-04
  (The Register 2026-02-20; VentureBeat 2026-05-13).
- OpenAI, https://developers.openai.com/siwc/token-sharing-open-source and
  sub-pages: "These docs explain ChatGPT plan usage for open-source and locally
  hosted apps. If you're interested in offering it in a paid or remotely hosted
  app, complete the interest form". Flow and endpoints match Pi's
  implementation (section 3.8). Pi issue
  https://github.com/earendil-works/pi/issues/10184 reports the consent page
  answering `invalid_client` for one account, closed as not planned - so
  eligibility can fail per account (UNCERTAIN why).
- OpenAI Codex CLI docs, https://learn.chatgpt.com/docs/auth and
  https://learn.chatgpt.com/docs/non-interactive-mode: Codex supports "Sign in
  with ChatGPT for subscription access"; credentials are cached in
  `~/.codex/auth.json` or the OS keyring; `codex exec` reuses saved CLI
  authentication. (This report did not read any credential file.)
- GitHub Copilot: Pi uses the VS Code Copilot Chat client id and editor
  identification headers. No statement from GitHub permitting this for
  third-party tools was found. UNCERTAIN; treat as not sanctioned.

### 2.14 System 1 (TypeSafe Jev) in Pi

VERIFIED (`types.ts:633-689`, `api/system-one-shared.ts`,
`api/typesafe-system-one.ts`, `docs/models.md:103-136`):

- Model type `classifier`, API id `typesafe-system-one`.
- Endpoint `POST {baseUrl}/systemone` (baseUrl `https://api.typesafe.ai/v1/`),
  headers `authorization: Bearer <TYPESAFE_API_KEY>`,
  `content-type: application/json`.
- Request body `{"model": "<id>", "state": {...}, "questions": {<name>:
  <question>}}` where a question is one of
  `{type:"choice", instructions, criteria:{<label>:<description>}}`,
  `{type:"score", instructions, criteria:[...]}`,
  `{type:"noul", instructions, criteria:{true:..., false:...}}` (Pi's public
  `bool` is rewritten to wire `noul`).
- Response `{"answers": {<name>: {type:"choice", choice, probabilities,
  confidence} | {type:"score", score, confidence} | {type:"noul", noul:
  <probability>}}, "usage": {input_tokens, output_tokens}}`.
- Default `maxRetries` 2; never rejects - errors come back as
  `stopReason: "error"` with `errorMessage`.
- Same protocol is served by OpenRouter (`/api/v1/systemone`), OpenCode Zen,
  Vercel AI Gateway (`/typesafe/v1/systemone`); Cloudflare Workers AI wraps it
  (`POST .../ai/run` with `{model, input}`; result under
  `result.result`).
- NOT verified against the live TypeSafe API (no key, no paid calls).

### 2.15 Retry, overflow and error normalisation

VERIFIED:

- Transport-level retry (`utils/provider-retry.ts`): retries when header
  `x-should-retry: true`, or no HTTP status, or status 408, 409, 429, >= 500;
  delay from `retry-after-ms`, else `retry-after` (seconds or HTTP date), else
  `min(0.5 * 2^n, 8)` seconds with up to 25% jitter; a server-requested delay
  above `maxRetryDelayMs` (60 s) fails immediately. Default `maxRetries` is 0
  at this layer.
- Agent-level retry (`utils/retry.ts`): classifies the final error message by
  regular expressions (overloaded, rate limit, 429/5xx, network errors,
  premature stream end, ...) and excludes quota/billing errors
  (`insufficient_quota`, `GoUsageLimitError`,
  `subscription_sharing_usage_limit_exceeded`, ...); backoff
  `baseDelayMs * 2^(attempt-1)` capped at 60 s.
- Context overflow detection (`utils/overflow.ts`): 24 regular expressions
  over `errorMessage` (verbatim list in the source), exclusion patterns for
  rate limits, plus "silent overflow" checks (`usage.input + cacheRead >
  contextWindow`, or `length` stop with zero output and a full window).
- Output budget clamp: `max_tokens = min(requested, contextWindow -
  estimatedContextTokens - 4096)`, at least 1 (`simple-options.ts:12-19`);
  token estimate is characters / 4, images count 4800 characters
  (`utils/estimate.ts:15-16`).
- Unpaired UTF-16 surrogates are stripped from all outgoing text
  (`utils/sanitize-unicode.ts`). R strings are UTF-8, so the equivalent R
  concern is invalid UTF-8 bytes: use `iconv(x, "UTF-8", "UTF-8", sub = "")`
  or `validUTF8()`.

---

## 3. Exact specifications

### 3.1 Unified types (verbatim from `packages/ai/src/types.ts`)

API and provider identifiers, levels (lines 17-37, 84-124):

```ts
export type KnownApi =
	| "openai-completions"
	| "mistral-conversations"
	| "openai-responses"
	| "azure-openai-responses"
	| "openai-codex-responses"
	| "anthropic-messages"
	| "bedrock-converse-stream"
	| "google-generative-ai"
	| "google-vertex"
	| "pi-messages";

export type Api = KnownApi | (string & {});

export type KnownImageApi = "openrouter-images";

export type ImageApi = KnownImageApi | (string & {});

export type KnownClassifierApi = "typesafe-system-one" | "cloudflare-workers-ai-system-one" | "llama-cpp-classify";

export type ClassifierApi = KnownClassifierApi | (string & {});
export type ToolChoice = "auto" | "none";
export type ThinkingLevel = "minimal" | "low" | "medium" | "high" | "xhigh" | "max";
export type ModelThinkingLevel = "off" | ThinkingLevel;
export type ThinkingLevelMap = Partial<Record<ModelThinkingLevel, string | null>>;
export type ChatTemplateKwargValue =
	| string
	| number
	| boolean
	| null
	| {
			$var: "thinking.enabled" | "thinking.effort" | "thinking.budget";
			omitWhenOff?: boolean;
	  };

/** Top-level request field used to cap reasoning tokens on OpenAI-compatible servers. */
export type ThinkingTokenBudgetField = "thinking_token_budget" | "thinking_budget" | "thinking_budget_tokens";

/** Token budgets for each thinking level (token-based providers only) */
export interface ThinkingBudgets {
	minimal?: number;
	low?: number;
	medium?: number;
	high?: number;
}

// Base options all providers share
export type CacheRetention = "none" | "short" | "long";

/**
 * Best-effort prompt cache lifetime in seconds for each retention tier a request can ask for.
 * A missing tier means the lifetime is unknown; pi does not warm such caches.
 */
export type ModelPromptCache = Partial<Record<Exclude<CacheRetention, "none">, number>>;

export type Transport = "sse" | "websocket" | "websocket-cached" | "auto";

/** Provider-scoped environment overrides. Values take precedence over process.env. */
export type ProviderEnv = Record<string, string>;
export type ProviderHeaders = Record<string, string | null>;
export type FetchFunction = typeof globalThis.fetch;
export type SessionAffinityFormat = "openai" | "openai-nosession" | "openrouter";
```

Content blocks, `Usage`, `StopReason` (lines 389-450):

```ts
export interface TextSignatureV1 {
	v: 1;
	id: string;
	phase?: "commentary" | "final_answer";
}

export interface TextContent {
	type: "text";
	text: string;
	textSignature?: string; // e.g., for OpenAI responses, message metadata (legacy id string or TextSignatureV1 JSON)
}

export interface ThinkingContent {
	type: "thinking";
	thinking: string;
	thinkingSignature?: string; // Provider-specific opaque or serialized reasoning replay data
	/** When true, the thinking content was redacted by safety filters. The opaque
	 *  encrypted payload is stored in `thinkingSignature` so it can be passed back
	 *  to the API for multi-turn continuity. */
	redacted?: boolean;
}

export interface ImageContent {
	type: "image";
	data: string; // base64 encoded image data
	mimeType: string; // e.g., "image/jpeg", "image/png"
}

export interface ToolCall {
	type: "toolCall";
	id: string;
	name: string;
	arguments: JsonObject;
	thoughtSignature?: string; // Google-specific: opaque signature for reusing thought context
	/** OpenAI Responses namespace for calls to dynamically loaded or namespaced tools. */
	namespace?: string;
}

export interface Usage {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	/** Subset of `cacheWrite` written with 1h retention. Only Anthropic reports this split. */
	cacheWrite1h?: number;
	/**
	 * Reasoning/thinking tokens, when the provider reports them. This is a subset of
	 * `output`: `output` already includes these tokens. Set to a number (possibly 0) by
	 * providers that expose a reasoning breakdown; left undefined by providers that don't.
	 */
	reasoning?: number;
	totalTokens: number;
	cost: {
		input: number;
		output: number;
		cacheRead: number;
		cacheWrite: number;
		total: number;
	};
}

export type StopReason = "pending" | "stop" | "length" | "toolUse" | "error" | "aborted" | "deferred";
```

Messages (lines 512-570, 594-610):

```ts
/**
 * System instructions and tool declarations at one point in the transcript.
 *
 * The leading system message is the system prompt. Later system messages change it:
 * `content` adds instructions from that point on, `sections` replace or remove named
 * prompt sections, and `toolsAdded`/`toolsRemoved` change the tool set. Replaying
 * every system message in order yields the current prompt and tools. Providers that
 * accept system messages mid-conversation send each one in place; other providers
 * rebuild the leading system message from the replayed state.
 */
export interface SystemMessage {
	role: "system";
	/** Instruction text. On the leading message this is the base prompt; later, additional instructions. */
	content: string | TextContent[];
	/**
	 * Named, ordered prompt sections rendered verbatim after `content`. The leading message
	 * declares them; later messages replace sections by name, and `null` removes one. Keep
	 * each section self-delimiting (a tag, a heading) so the model can relate an update to
	 * the original. Avoid integer-like names; JSON objects reorder those.
	 */
	sections?: Record<string, string | null>;
	/** Complete definitions of tools that become available at this point. */
	toolsAdded?: Tool[];
	/** Tools that stop being available at this point. */
	toolsRemoved?: ToolReference[];
	timestamp: number; // Unix timestamp in milliseconds
}

export interface UserMessage {
	role: "user";
	content: string | (TextContent | ImageContent)[];
	timestamp: number; // Unix timestamp in milliseconds
}

export interface AssistantMessage {
	role: "assistant";
	content: (TextContent | ThinkingContent | ToolCall)[];
	api: Api;
	provider: ProviderId;
	model: string;
	responseModel?: string; // Concrete model reported by the provider when different from the requested `model`
	responseId?: string; // Provider-specific response/message identifier when the upstream API exposes one
	/** Exact provider-native effort level used for this response. Absent for legacy or unmanaged responses. */
	providerThinkingLevel?: string;
	/** Pi thinking level the agent loop requested for this response. Absent outside the agent loop and for legacy responses. */
	thinkingLevel?: ModelThinkingLevel;
	diagnostics?: AssistantMessageDiagnostic[]; // Redacted provider/runtime diagnostics for failures and recoveries.
	usage: Usage;
	stopReason: StopReason;
	deferred?: DeferredHandle;
	errorMessage?: string;
	rawStopReason?: string;
	/**
	 * Provider indication of whether the model explicitly ended its turn.
	 * Preserved for debugging and does not currently affect agent control flow.
	 */
	endTurn?: boolean;
	timestamp: number; // Unix timestamp in milliseconds
}
export type ToolResultMessage<TDetails = JsonValue> = IsJsonCompatible<TDetails> extends true
	? {
			role: "toolResult";
			toolCallId: string;
			toolName: string;
			content: (TextContent | ImageContent)[]; // Supports text and images
			details?: JsonRepresentation<TDetails>;
			/** Usage from the tool execution itself, if available. Not part of main LLM context accounting. */
			usage?: Usage;
			/** Calls this tool made to other tools. Kept for the session record; not sent to the model. */
			nestedCalls?: NestedToolCalls;
			isError: boolean;
			timestamp: number; // Unix timestamp in milliseconds
		}
	: never;

export type Message = SystemMessage | UserMessage | AssistantMessage | ToolResultMessage;
```

`Tool`, `Context` (lines 715-749):

```ts
export interface Tool<TParameters extends TSchema = TSchema> {
	name: string;
	description: string;
	parameters: TParameters;
	constrainedSampling?: false | ConstrainedSamplingConfig;
}

export interface ToolReference {
	name: string;
}

/**
 * Request input accepted by the public stream entry points (`Models.stream()`,
 * `streamSimple()`, ...). `systemPrompt` and `tools` are shorthand for a leading
 * system message; `normalizeContext()` folds them into one before the request
 * reaches a provider.
 */
export interface Context {
	systemPrompt?: string;
	messages: Message[];
	tools?: Tool[];
}

declare const transcriptContextBrand: unique symbol;

/**
 * Normalized request context passed to providers and API implementations. The
 * prompt and tool declarations are carried by the transcript's system messages.
 * Only `normalizeContext()` produces this type, so a raw `Context` cannot reach
 * provider code by accident.
 */
export type TranscriptContext = {
	messages: Message[];
	readonly [transcriptContextBrand]: true;
};
```

`SimpleStreamOptions` (lines 349-358) and `StreamOptions` (lines 187-237):

```ts
// Unified options with reasoning passed to streamSimple() and completeSimple()
export interface SimpleStreamOptions extends StreamOptions {
	/** Provider-neutral tool selection for simple requests. When omitted, adapters use provider-specific behavior. */
	toolChoice?: ToolChoice;
	reasoning?: ThinkingLevel;
	/** Ask a capable provider to return a durable handle and continue the request asynchronously. */
	deferred?: boolean | { window?: "15m" | "1h" | "24h" };
	/** Custom token budgets for thinking levels (token-based providers only) */
	thinkingBudgets?: ThinkingBudgets;
}
export interface StreamOptions extends ProviderRequestOptions<Model<Api>> {
	/**
	 * Optional callback invoked after an HTTP response is received and before
	 * its body stream is consumed.
	 */
	onResponse?: (response: ProviderResponse, model: Model<Api>) => void | Promise<void>;
	/**
	 * Optional observer for each parsed provider stream event before Pi normalization.
	 * Event data is adapter-owned and must be treated as read-only.
	 * Adapter support is explicit; unsupported adapters do not invoke it.
	 */
	onProviderStreamEvent?: (data: unknown, model: Model<Api>) => void | Promise<void>;
	temperature?: number;
	/**
	 * Arbitrary sampling parameters merged into the request body as-is, after the named request
	 * fields, so keys here override them. Lets custom OpenAI-compatible servers (llama.cpp, vLLM,
	 * SGLang, ...) receive parameters pi does not model, e.g. `top_p`, `top_k`, `min_p`,
	 * `repetition_penalty`. Merged over `Model.samplingParams` per key. Only applied by
	 * OpenAI-compatible adapters (completions, responses, Azure responses); other APIs ignore it.
	 */
	samplingParams?: Record<string, unknown>;
	maxTokens?: number;
	/**
	 * Preferred transport for providers that support multiple transports.
	 * Providers that do not support this option ignore it.
	 */
	transport?: Transport;
	/**
	 * Prompt cache retention preference. Providers map this to their supported values.
	 * Default: "short".
	 */
	cacheRetention?: CacheRetention;
	/**
	 * Optional session identifier for providers that support session-based caching.
	 * Providers can use this to enable prompt caching, request routing, or other
	 * session-aware features. Ignored by providers that don't support it.
	 */
	sessionId?: string;
	/**
	 * WebSocket connect timeout in milliseconds for providers that support
	 * WebSocket transports. This covers the connection/open handshake only;
	 * stream idleness after connection uses timeoutMs.
	 */
	websocketConnectTimeoutMs?: number;
	/**
	 * Optional metadata to include in API requests.
	 * Providers extract the fields they understand and ignore the rest.
	 * For example, Anthropic uses `user_id` for abuse tracking and rate limiting.
	 */
	metadata?: Record<string, unknown>;
}
```

Cost and model records (lines 1056-1071, 1096-1168):

```ts
export interface ModelCostRates {
	input: number; // $/million tokens
	output: number; // $/million tokens
	cacheRead: number; // $/million tokens
	cacheWrite: number; // $/million tokens
}

export interface ModelCostTier extends ModelCostRates {
	/** Use this tier for requests whose total input usage exceeds this token count. */
	inputTokensAbove: number;
}

export interface ModelCost extends ModelCostRates {
	/** Request-wide pricing tiers. The highest matching input threshold applies to the full request. */
	tiers?: ModelCostTier[];
}
/** Fields shared by every catalog entry, regardless of what you can do with it. */
export interface BaseModel<TApi extends string> {
	id: string;
	name: string;
	api: TApi;
	provider: ProviderId;
	baseUrl: string;
	input: ("text" | "image")[];
	/** Provider input limits and cache-safe preprocessing metadata. */
	inputLimits?: ModelInputLimits;
	cost: ModelCost;
	headers?: Record<string, string>;
}

/** Chat model: usable with `stream()` and friends. */
export interface Model<TApi extends Api> extends BaseModel<TApi> {
	/**
	 * Optional: chat is the default model type, so models without `type` are chat
	 * models. Narrow mixed model lists with `isModelType()` instead of comparing
	 * `type` directly.
	 */
	type?: "chat";
	reasoning: boolean;
	/**
	 * Maps pi thinking levels to provider/model-specific values.
	 * Missing keys use provider defaults. null marks a level as unsupported.
	 */
	thinkingLevelMap?: ThinkingLevelMap;
	/** Prompt cache lifetimes per retention tier. Unset when the provider's cache behavior is unknown. */
	promptCache?: ModelPromptCache;
	contextWindow: number;
	maxTokens: number;
	/** Default sampling parameters for this model. See {@link StreamOptions.samplingParams}; per-request keys override these. */
	samplingParams?: Record<string, unknown>;
	/** Compatibility overrides for OpenAI-compatible APIs. If not set, auto-detected from baseUrl. */
	compat?: TApi extends "openai-completions"
		? OpenAICompletionsCompat
		: TApi extends "openai-responses" | "azure-openai-responses" | "openai-codex-responses"
			? OpenAIResponsesCompat
			: TApi extends "anthropic-messages"
				? AnthropicMessagesCompat
				: TApi extends "bedrock-converse-stream"
					? BedrockCompat
					: TApi extends "mistral-conversations"
						? MistralConversationsCompat
						: never;
}

/** Image-generation model: usable with `generateImages()` only. */
export interface ImageModel<TApi extends ImageApi> extends BaseModel<TApi> {
	type: "image";
	/** Output modalities. Always includes `"image"`; `"text"` means the model can also return text blocks. */
	output: ("text" | "image")[];
}

/** Structured classifier model: usable with `classify()` only. */
export interface ClassifierModel<TApi extends ClassifierApi> extends BaseModel<TApi> {
	type: "classifier";
	contextWindow: number;
}

/** Model shape for each model type. */
export interface ModelTypeMap {
	chat: Model<Api>;
	image: ImageModel<ImageApi>;
	classifier: ClassifierModel<ClassifierApi>;
}

/** What a catalog entry is for. Decides which `Models` operation accepts it. */
export type ModelType = keyof ModelTypeMap;

/** Anything a provider can list. Narrow with `isModelType()`. */
export type AnyModel = ModelTypeMap[ModelType];
```

Classifier (System 1) types (lines 633-689):

```ts
export interface ClassifierChoiceQuestion {
	type: "choice";
	instructions: string;
	criteria: Record<string, string>;
}

export interface ClassifierScoreQuestion {
	type: "score";
	instructions: string;
	criteria: string[];
}

export interface ClassifierBoolQuestion {
	type: "bool";
	instructions: string;
	criteria: { true: string; false: string };
}

export type ClassifierQuestion = ClassifierChoiceQuestion | ClassifierScoreQuestion | ClassifierBoolQuestion;

export interface ClassifierContext {
	state: JsonObject;
	questions: Record<string, ClassifierQuestion>;
}

export interface ClassifierChoiceAnswer {
	type: "choice";
	choice: string;
	probabilities: Record<string, number>;
	confidence: number;
}

export interface ClassifierScoreAnswer {
	type: "score";
	score: number;
	confidence: number;
}

export interface ClassifierBoolAnswer {
	type: "bool";
	probability: number;
}

export type ClassifierAnswer = ClassifierChoiceAnswer | ClassifierScoreAnswer | ClassifierBoolAnswer;
export type ClassifierStopReason = "stop" | "error" | "aborted";

export interface ClassifierResult {
	api: ClassifierApi;
	provider: ProviderId;
	model: string;
	answers: Record<string, ClassifierAnswer>;
	/** Token usage and its cost at the model's catalog price, when the service reports token counts. */
	usage?: Usage;
	stopReason: ClassifierStopReason;
	errorMessage?: string;
	timestamp: number; // Unix timestamp in milliseconds
}
```

### 3.2 Streaming event protocol (verbatim, `types.ts:751-783`)

```ts
/**
 * Event protocol for AssistantMessageEventStream.
 *
 * Successful streams emit `start` before partial updates and terminate with
 * `done`. A stream may terminate directly with `error` when request setup fails
 * before generation starts; after `start`, failures also terminate with `error`.
 * Direct `streamSimple()` calls throw synchronously when request auth is missing.
 * Updates and `done` must never appear before `start`.
 *
 * `partial` is the shared live response-so-far helper, not an event-time
 * snapshot. Text and thinking blocks are empty when their `*_start` event is
 * emitted and grow only through their corresponding `*_delta` events until the
 * authoritative `*_end`. Redacted thinking may be complete at start and emit no
 * deltas. Tool-call arguments at `toolcall_start` are provider-specific;
 * `toolcall_delta` carries subsequent JSON updates.
 */
export type AssistantMessageEvent =
	| { type: "start"; partial: AssistantMessage }
	| { type: "text_start"; contentIndex: number; partial: AssistantMessage }
	| { type: "text_delta"; contentIndex: number; delta: string; partial: AssistantMessage }
	| { type: "text_end"; contentIndex: number; content: string; partial: AssistantMessage }
	| { type: "thinking_start"; contentIndex: number; partial: AssistantMessage }
	| { type: "thinking_delta"; contentIndex: number; delta: string; partial: AssistantMessage }
	| { type: "thinking_end"; contentIndex: number; content: string; partial: AssistantMessage }
	| { type: "toolcall_start"; contentIndex: number; partial: AssistantMessage }
	| { type: "toolcall_delta"; contentIndex: number; delta: string; partial: AssistantMessage }
	| { type: "toolcall_end"; contentIndex: number; toolCall: ToolCall; partial: AssistantMessage }
	| {
			type: "done";
			reason: Extract<StopReason, "stop" | "length" | "toolUse" | "deferred">;
			message: AssistantMessage;
	  }
	| { type: "error"; reason: Extract<StopReason, "aborted" | "error">; error: AssistantMessage };
```

### 3.3 Compatibility flag records (verbatim, `types.ts:785-967`)

```ts
/**
 * Compatibility settings for OpenAI-compatible completions APIs.
 * Use this to override URL-based auto-detection for custom providers.
 */
export interface OpenAICompletionsCompat {
	/** Whether the provider supports the `store` field. Default: auto-detected from URL. */
	supportsStore?: boolean;
	/** Whether the provider supports the `developer` role (vs `system`). Default: auto-detected from URL. */
	supportsDeveloperRole?: boolean;
	/** Whether the provider supports `reasoning_effort`. Default: auto-detected from URL. */
	supportsReasoningEffort?: boolean;
	/** Whether the provider supports `stream_options: { include_usage: true }` for token usage in streaming responses. Default: true. */
	supportsUsageInStreaming?: boolean;
	/** Whether streamed responses include `finish_reason`. When false, pi infers `stop` or `toolUse` when the stream ends. Default: true. */
	supportsFinishReason?: boolean;
	/** Which field to use for max tokens. Default: auto-detected from URL. */
	maxTokensField?: "max_completion_tokens" | "max_tokens";
	/** Whether tool results require the `name` field. Default: auto-detected from URL. */
	requiresToolResultName?: boolean;
	/** Whether a user message after tool results requires an assistant message in between. Default: auto-detected from URL. */
	requiresAssistantAfterToolResult?: boolean;
	/** Whether thinking blocks must be converted to text blocks with <thinking> delimiters. Default: auto-detected from URL. */
	requiresThinkingAsText?: boolean;
	/** Whether all replayed assistant messages must include an empty reasoning_content field when reasoning is enabled. Default: auto-detected from URL. */
	requiresReasoningContentOnAssistantMessages?: boolean;
	/** Format for reasoning/thinking parameter. "openai" uses reasoning_effort, "openrouter" uses reasoning: { effort }, "deepseek" uses thinking: { type } plus reasoning_effort when supported, "together" uses reasoning: { enabled } plus reasoning_effort when supported, "baseten" uses configurable chat_template_args plus reasoning_effort when supported, "zai" uses thinking: { type }, "qwen" uses top-level enable_thinking: boolean, "qwen-chat-template" uses chat_template_kwargs.enable_thinking and preserve_thinking, "chat-template" uses configurable chat_template_kwargs, "string-thinking" uses top-level thinking: string, and "ant-ling" uses reasoning: { effort } only when the mapped effort is non-null. Default: "openai". */
	thinkingFormat?:
		| "openai"
		| "openrouter"
		| "deepseek"
		| "together"
		| "baseten"
		| "zai"
		| "qwen"
		| "chat-template"
		| "qwen-chat-template"
		| "string-thinking"
		| "ant-ling";
	/** Kwargs to send as `chat_template_kwargs` when `thinkingFormat` is `chat-template`. Use `{ "$var": "thinking.enabled" }`, `{ "$var": "thinking.effort" }`, or `{ "$var": "thinking.budget" }` for pi-controlled thinking values. */
	chatTemplateKwargs?: Record<string, ChatTemplateKwargValue>;
	/** Arguments to send as `chat_template_args` when `thinkingFormat` is `baseten`. Use `{ "$var": "thinking.enabled" }`, `{ "$var": "thinking.effort" }`, or `{ "$var": "thinking.budget" }` for pi-controlled thinking values. */
	chatTemplateArgs?: Record<string, ChatTemplateKwargValue>;
	/** OpenRouter-compatible routing preferences sent as the `provider` request field. */
	openRouterRouting?: OpenRouterRouting;
	/** Vercel AI Gateway routing preferences. Only used when baseUrl points to Vercel AI Gateway. */
	vercelGatewayRouting?: VercelGatewayRouting;
	/** Whether z.ai supports top-level `tool_stream: true` for streaming tool call deltas. Default: false. */
	zaiToolStream?: boolean;
	/**
	 * Top-level request field used to cap reasoning tokens from `thinkingBudgets`.
	 * Reasoning and the answer share `max_tokens` on these endpoints, so without a budget a
	 * reasoning-heavy turn can consume the whole response and emit no answer.
	 * `"thinking_token_budget"` is vLLM, `"thinking_budget"` is Qwen/DashScope/SGLang,
	 * `"thinking_budget_tokens"` is llama.cpp. Off by default; not set on the generated catalog.
	 */
	thinkingTokenBudgetField?: ThinkingTokenBudgetField;
	/** Alias for `thinkingTokenBudgetField: "thinking_token_budget"` (vLLM). Prefer `thinkingTokenBudgetField`. Default: false. */
	supportsThinkingTokenBudget?: boolean;
	/** Whether the provider supports OpenAI custom tools with Lark/regex grammar formats. When false, grammar-constrained tools fall back to normal function tools. Default: false; the generated model catalog enables it for capable models. */
	supportsOpenAIGrammarTools?: boolean;
	/** Whether the exact model accepts system or developer messages after the conversation has started. When false, later system messages are folded into the leading system message. Default: false; the generated model catalog enables it for verified models. */
	supportsMidConvoSystemMessages?: boolean;
	/** Whether system messages can introduce additional tools mid-conversation. Requires `supportsMidConvoSystemMessages`. Default: false; the generated model catalog enables it for capable models. */
	supportsMidConvoToolAdditions?: boolean;
	/** Whether the provider supports the `strict` field in tool definitions. Default: false; generated capable models enable it explicitly. */
	supportsStrictMode?: boolean;
	/** Cache control convention for prompt caching. "anthropic" applies Anthropic-style `cache_control` markers to the system prompt, last tool definition, and last user, assistant, or tool-result text content. */
	cacheControlFormat?: "anthropic";
	/** Whether to send session-affinity data from `options.sessionId`. Default: true for OpenRouter endpoints, false otherwise. */
	sendSessionAffinityHeaders?: boolean;
	/** Session-affinity header format: `openai` sends `session_id`, `x-client-request-id`, and `x-session-affinity`; `openai-nosession` sends `x-client-request-id` and `x-session-affinity`; `openrouter` sends `x-session-id`. Does not affect the `prompt_cache_key` body param, which is governed by cache retention. Default: auto-detected. */
	sessionAffinityFormat?: SessionAffinityFormat;
	/** Whether the provider supports long prompt cache retention (`prompt_cache_retention: "24h"` or Anthropic-style `cache_control.ttl: "1h"`, depending on format). Default: true. */
	supportsLongCacheRetention?: boolean;
	/**
	 * vLLM scheduler priority sent as the top-level `priority` request field (lower values are
	 * handled earlier; server default 0). Only meaningful when vLLM runs with
	 * `--scheduling-policy priority`; useful for keeping background/batch work from stalling
	 * interactive sessions. Off by default; not set on the generated catalog.
	 */
	vllmPriority?: number;
}

/** Compatibility settings for OpenAI Responses APIs. */
export interface OpenAIResponsesCompat {
	/** Whether the provider supports the `developer` role (vs `system`). Default: true. */
	supportsDeveloperRole?: boolean;
	/** Whether the exact model accepts developer or system messages after the conversation has started. When false, later system messages are folded into the leading system message. Default: false; the generated model catalog enables it for verified models. */
	supportsMidConvoSystemMessages?: boolean;
	/** Session-affinity header format: `openai` sends `session_id` and `x-client-request-id`; `openai-nosession` sends `x-client-request-id`; `openrouter` sends `x-session-id`. Does not affect the `prompt_cache_key` body param, which is governed by cache retention. Default: auto-detected. */
	sessionAffinityFormat?: SessionAffinityFormat;
	/** Whether the provider supports long prompt cache retention. This uses `prompt_cache_options.ttl: "30m"` on GPT-5.6+ and `prompt_cache_retention: "24h"` on earlier models. Default: true. */
	supportsLongCacheRetention?: boolean;
	/** Whether the provider supports strict JSON-schema function tools. Defaults are API-specific; generated OpenAI models enable it explicitly. */
	supportsStrictMode?: boolean;
	/** Whether to emit OpenAI custom tools with Lark/regex grammar formats. When false, grammar-constrained tools fall back to normal function tools. Default: false; the generated model catalog enables it for capable models. */
	supportsOpenAIGrammarTools?: boolean;
	/** Whether the model supports message-anchored `additional_tools` input items. Default: false. */
	supportsAdditionalTools?: boolean;
	/** Whether the model supports client-executed tool search for transcript-anchored additions. Default: false. */
	supportsToolSearch?: boolean;
	/** Whether the model accepts `prompt_cache_options` (OpenAI GPT-5.6+ prompt caching). Older OpenAI models reject the parameter. Default: false. */
	supportsExplicitPromptCacheMode?: boolean;
	/** Whether the provider accepts the `max_output_tokens` parameter. Some Codex-protocol gateways reject it. Default: true. */
	supportsMaxOutputTokens?: boolean;
}

/** Compatibility settings for Anthropic Messages-compatible APIs. */
export interface AnthropicMessagesCompat {
	/**
	 * Whether the provider accepts per-tool `eager_input_streaming`.
	 * When false, the Anthropic provider omits `tools[].eager_input_streaming`
	 * and sends the legacy `fine-grained-tool-streaming-2025-05-14` beta header
	 * for tool-enabled requests.
	 * Default: true.
	 */
	supportsEagerToolInputStreaming?: boolean;
	/** Whether the provider supports Anthropic long cache retention (`cache_control.ttl: "1h"`). Default: true. */
	supportsLongCacheRetention?: boolean;
	/**
	 * Whether to send the `x-session-affinity` header from `options.sessionId`
	 * when caching is enabled. Required for providers like Fireworks that use
	 * session affinity for prompt cache routing (requests to the same replica
	 * maximize cache hits).
	 * Default: false.
	 */
	sendSessionAffinityHeaders?: boolean;
	/** Session-affinity format. `"openrouter"` sends `x-session-id`; when unset, sends `x-session-affinity`. */
	sessionAffinityFormat?: "openrouter";
	/**
	 * Whether the provider supports Anthropic-style `cache_control` markers on
	 * tool definitions. When false, `cache_control` is omitted from tool params.
	 * Some Anthropic-compatible providers (e.g., Fireworks) do not support this
	 * field on tools and may reject or ignore it.
	 * Default: true.
	 */
	supportsCacheControlOnTools?: boolean;
	/**
	 * Whether the model accepts the Anthropic `temperature` request field.
	 * Claude Opus 4.7+ rejects non-default temperature values.
	 * Default: true.
	 */
	supportsTemperature?: boolean;
	/**
	 * Whether to force adaptive thinking (`thinking.type: "adaptive"` plus
	 * `output_config.effort`) regardless of the model id. Built-in models that
	 * require adaptive thinking set this in generated metadata. Custom
	 * Anthropic-compatible providers can set this to `true` for any model whose
	 * upstream requires the adaptive format. Set to `false` to
	 * opt out on overridden built-in models.
	 * Default: false.
	 */
	forceAdaptiveThinking?: boolean;
	/** Whether to replay empty thinking signatures as `signature: ""` instead of converting thinking to text. Default: false. */
	allowEmptySignature?: boolean;
	/** Whether the provider supports Anthropic strict tool schemas. Default: false; generated Anthropic models enable it explicitly. */
	supportsStrictTools?: boolean;
	/** Whether the exact model transport supports effort-only system messages and thinking binding controls. Default: false. */
	supportsMidConvoEffort?: boolean;
	/** Whether the exact model accepts system-role messages inside the conversation. When false, later system messages are folded into the top-level system prompt. Default: false. */
	supportsMidConvoSystemMessages?: boolean;
	/** Whether the exact model accepts mid-conversation `tool_addition` and `tool_removal` blocks. Requires `supportsMidConvoSystemMessages`. Default: false. */
	supportsMidConvoToolChanges?: boolean;
	/**
	 * Models Anthropic accepts in `fallbacks` for server-side refusal fallback,
	 * with local pricing metadata for returned fallback responses. When absent or
	 * empty, callers must omit `fallbacks`; Anthropic rejects the field for models
	 * with no permitted fallback targets.
	 */
	allowedFallbackModels?: AnthropicAllowedFallbackModel[];
}

/** Compatibility settings for Amazon Bedrock models. */
export interface BedrockCompat {
	/** Whether the model supports Bedrock strict tool schemas. Default: false. */
	supportsStrictMode?: boolean;
}

/** Compatibility settings for the Mistral chat API. */
export interface MistralConversationsCompat {
	/** Whether the exact model accepts system messages after the conversation has started. When false, later system messages are folded into the leading system message. Default: false. */
	supportsMidConvoSystemMessages?: boolean;
}
```

### 3.4 Cost and thinking-level functions (verbatim)

`packages/ai/src/models.ts:1193-1247`:

```ts
export function calculateCost(model: AnyModel, usage: Usage): Usage["cost"] {
	const inputTokens = usage.input + usage.cacheRead + usage.cacheWrite;
	let rates: ModelCostRates = model.cost;
	let matchedThreshold = -1;
	for (const tier of model.cost.tiers ?? []) {
		if (inputTokens > tier.inputTokensAbove && tier.inputTokensAbove > matchedThreshold) {
			rates = tier;
			matchedThreshold = tier.inputTokensAbove;
		}
	}

	// Anthropic charges 2x base input for 1h cache writes.
	const longWrite = usage.cacheWrite1h ?? 0;
	const shortWrite = usage.cacheWrite - longWrite;
	usage.cost.input = (rates.input / 1000000) * usage.input;
	usage.cost.output = (rates.output / 1000000) * usage.output;
	usage.cost.cacheRead = (rates.cacheRead / 1000000) * usage.cacheRead;
	usage.cost.cacheWrite = (rates.cacheWrite * shortWrite + rates.input * 2 * longWrite) / 1000000;
	usage.cost.total = usage.cost.input + usage.cost.output + usage.cost.cacheRead + usage.cost.cacheWrite;
	return usage.cost;
}

const EXTENDED_THINKING_LEVELS: ModelThinkingLevel[] = ["off", "minimal", "low", "medium", "high", "xhigh", "max"];

export function getSupportedThinkingLevels<TApi extends Api>(model: Model<TApi>): ModelThinkingLevel[] {
	if (!model.reasoning) return ["off"];

	return EXTENDED_THINKING_LEVELS.filter((level) => {
		const mapped = model.thinkingLevelMap?.[level];
		if (mapped === null) return false;
		if (level === "xhigh" || level === "max") return mapped !== undefined;
		return true;
	});
}

export function clampThinkingLevel<TApi extends Api>(
	model: Model<TApi>,
	level: ModelThinkingLevel,
): ModelThinkingLevel {
	const availableLevels = getSupportedThinkingLevels(model);
	if (availableLevels.includes(level)) return level;

	const requestedIndex = EXTENDED_THINKING_LEVELS.indexOf(level);
	if (requestedIndex === -1) return availableLevels[0] ?? "off";

	for (let i = requestedIndex; i < EXTENDED_THINKING_LEVELS.length; i++) {
		const candidate = EXTENDED_THINKING_LEVELS[i];
		if (availableLevels.includes(candidate)) return candidate;
	}
	for (let i = requestedIndex - 1; i >= 0; i--) {
		const candidate = EXTENDED_THINKING_LEVELS[i];
		if (availableLevels.includes(candidate)) return candidate;
	}
	return availableLevels[0] ?? "off";
}
```

`packages/ai/src/api/simple-options.ts:12-19, 51-92`:

```ts
const CONTEXT_SAFETY_TOKENS = 4096;
const MIN_MAX_TOKENS = 1;

export function clampMaxTokensToContext(model: Model<Api>, context: TranscriptContext, maxTokens: number): number {
	if (model.contextWindow <= 0) return Math.max(MIN_MAX_TOKENS, maxTokens);
	const available = model.contextWindow - estimateContextTokens(context).tokens - CONTEXT_SAFETY_TOKENS;
	return Math.min(maxTokens, Math.max(MIN_MAX_TOKENS, available));
}
/** Tokens always left for the answer when a thinking budget shares the response ceiling. */
export const MIN_ANSWER_TOKENS = 1024;

export const DEFAULT_THINKING_BUDGETS: ThinkingBudgets = {
	minimal: 1024,
	low: 2048,
	medium: 8192,
	high: 16384,
};

export function clampReasoning(effort: ThinkingLevel | undefined): Exclude<ThinkingLevel, "xhigh" | "max"> | undefined {
	return effort === "xhigh" || effort === "max" ? "high" : effort;
}

export function thinkingBudgetForLevel(reasoningLevel: ThinkingLevel, customBudgets?: ThinkingBudgets): number {
	const budgets = { ...DEFAULT_THINKING_BUDGETS, ...customBudgets };
	const level = clampReasoning(reasoningLevel)!;
	return budgets[level]!;
}

/** Cap a thinking budget so at least MIN_ANSWER_TOKENS remain under a shared response ceiling. */
export function clampThinkingBudgetToAnswerRoom(thinkingBudget: number, ceiling: number): number {
	return Math.min(thinkingBudget, Math.max(0, ceiling - MIN_ANSWER_TOKENS));
}

export function adjustMaxTokensForThinking(
	// Undefined means no explicit caller cap. Use the model cap and fit thinking inside it.
	baseMaxTokens: number | undefined,
	modelMaxTokens: number,
	reasoningLevel: ThinkingLevel,
	customBudgets?: ThinkingBudgets,
): { maxTokens: number; thinkingBudget: number } {
	let thinkingBudget = thinkingBudgetForLevel(reasoningLevel, customBudgets);
	const maxTokens =
		baseMaxTokens === undefined ? modelMaxTokens : Math.min(baseMaxTokens + thinkingBudget, modelMaxTokens);

	if (maxTokens <= thinkingBudget) {
		thinkingBudget = clampThinkingBudgetToAnswerRoom(thinkingBudget, maxTokens);
	}

	return { maxTokens, thinkingBudget };
}
```

### 3.5 Partial JSON and message transformation (verbatim)

`packages/ai/src/utils/json-parse.ts:27-124`:

```ts
/**
 * Repairs malformed JSON string literals by:
 * - escaping raw control characters inside strings
 * - doubling backslashes before invalid escape characters
 */
export function repairJson(json: string): string {
	let repaired = "";
	let inString = false;

	for (let index = 0; index < json.length; index++) {
		const char = json[index];

		if (!inString) {
			repaired += char;
			if (char === '"') {
				inString = true;
			}
			continue;
		}

		if (char === '"') {
			repaired += char;
			inString = false;
			continue;
		}

		if (char === "\\") {
			const nextChar = json[index + 1];
			if (nextChar === undefined) {
				repaired += "\\\\";
				continue;
			}

			if (nextChar === "u") {
				const unicodeDigits = json.slice(index + 2, index + 6);
				if (/^[0-9a-fA-F]{4}$/.test(unicodeDigits)) {
					repaired += `\\u${unicodeDigits}`;
					index += 5;
					continue;
				}
			}

			if (VALID_JSON_ESCAPES.has(nextChar)) {
				repaired += `\\${nextChar}`;
				index += 1;
				continue;
			}

			repaired += "\\\\";
			continue;
		}

		repaired += isControlCharacter(char) ? escapeControlCharacter(char) : char;
	}

	return repaired;
}

export function parseJsonWithRepair<T>(json: string): T {
	try {
		return JSON.parse(json) as T;
	} catch (error) {
		const repairedJson = repairJson(json);
		if (repairedJson !== json) {
			return JSON.parse(repairedJson) as T;
		}
		throw error;
	}
}

/**
 * Attempts to parse potentially incomplete JSON during streaming.
 * Always returns a valid object, even if the JSON is incomplete.
 *
 * @param partialJson The partial JSON string from streaming
 * @returns Parsed object or empty object if parsing fails
 */
export function parseStreamingJson<T = Record<string, unknown>>(partialJson: string | undefined): T {
	if (!partialJson || partialJson.trim() === "") {
		return {} as T;
	}

	try {
		return parseJsonWithRepair<T>(partialJson);
	} catch {
		try {
			const result = partialParse(partialJson);
			return (result ?? {}) as T;
		} catch {
			try {
				const result = partialParse(repairJson(partialJson));
				return (result ?? {}) as T;
			} catch {
				return {} as T;
			}
		}
	}
}
```

`packages/ai/src/api/transform-messages.ts:59-235`:

```ts
/**
 * Normalize tool call ID for cross-provider compatibility.
 * OpenAI Responses API generates IDs that are 450+ chars with special characters like `|`.
 * Anthropic APIs require IDs matching ^[a-zA-Z0-9_-]+$ (max 64 chars).
 */
export function transformMessages<TApi extends Api>(
	messages: Message[],
	model: Model<TApi>,
	normalizeToolCallId?: (id: string, model: Model<TApi>, source: AssistantMessage) => string,
): Message[] {
	// Build a map of original tool call IDs to normalized IDs
	const toolCallIdMap = new Map<string, string>();
	// Normalize null/undefined content from untyped callers (custom tools, hand-built
	// histories, old session files) so downstream code can rely on the type contract.
	const normalizedMessages = messages.map((msg) => (msg.content == null ? { ...msg, content: [] } : msg));
	const imageAwareMessages = downgradeUnsupportedImages(normalizedMessages, model);

	// First pass: transform messages (unsupported image downgrade, thinking blocks, tool call ID normalization)
	const transformed = imageAwareMessages.map((msg) => {
		// System and user messages pass through unchanged
		if (msg.role === "system" || msg.role === "user") {
			return msg;
		}

		// Handle toolResult messages - normalize toolCallId if we have a mapping
		if (msg.role === "toolResult") {
			const normalizedId = toolCallIdMap.get(msg.toolCallId);
			if (normalizedId && normalizedId !== msg.toolCallId) {
				return { ...msg, toolCallId: normalizedId };
			}
			return msg;
		}

		// Assistant messages need transformation check
		if (msg.role === "assistant") {
			const assistantMsg = msg as AssistantMessage;
			const isSameModel =
				assistantMsg.provider === model.provider &&
				assistantMsg.api === model.api &&
				assistantMsg.model === model.id;

			const transformedContent = assistantMsg.content.flatMap((block) => {
				if (block.type === "thinking") {
					// Redacted thinking is opaque encrypted content, only valid for the same model.
					// Drop it for cross-model to avoid API errors.
					if (block.redacted) {
						return isSameModel ? block : [];
					}
					// For same model: keep thinking blocks with signatures (needed for replay)
					// even if the thinking text is empty (OpenAI encrypted reasoning)
					if (isSameModel && block.thinkingSignature) return block;
					// Skip empty thinking blocks, convert others to plain text
					if (!block.thinking || block.thinking.trim() === "") return [];
					if (isSameModel) return block;
					return {
						type: "text" as const,
						text: block.thinking,
					};
				}

				if (block.type === "text") {
					if (isSameModel) return block;
					return {
						type: "text" as const,
						text: block.text,
					};
				}

				if (block.type === "toolCall") {
					const toolCall = block as ToolCall;
					let normalizedToolCall: ToolCall = toolCall;

					if (!isSameModel && toolCall.thoughtSignature) {
						normalizedToolCall = { ...toolCall };
						delete (normalizedToolCall as { thoughtSignature?: string }).thoughtSignature;
					}

					if (!isSameModel && normalizeToolCallId) {
						const normalizedId = normalizeToolCallId(toolCall.id, model, assistantMsg);
						if (normalizedId !== toolCall.id) {
							toolCallIdMap.set(toolCall.id, normalizedId);
							normalizedToolCall = { ...normalizedToolCall, id: normalizedId };
						}
					}

					return normalizedToolCall;
				}

				return block;
			});

			return {
				...assistantMsg,
				content: transformedContent,
			};
		}
		return msg;
	});

	// Second pass: insert synthetic empty tool results for orphaned tool calls
	// This preserves thinking signatures and satisfies API requirements
	const result: Message[] = [];
	let pendingToolCalls: ToolCall[] = [];
	let existingToolResultIds = new Set<string>();
	// System messages are transparent to tool-call accounting: one that lands between a tool
	// call and its results is held back and emitted after the results (synthetic ones
	// included), so it never causes a duplicate result for a call that is answered later.
	const heldSystemMessages: Message[] = [];
	const closePendingToolCalls = () => {
		if (pendingToolCalls.length > 0) {
			for (const tc of pendingToolCalls) {
				if (!existingToolResultIds.has(tc.id)) {
					result.push({
						role: "toolResult",
						toolCallId: tc.id,
						toolName: tc.name,
						content: [{ type: "text", text: "No result provided" }],
						isError: true,
						timestamp: Date.now(),
					} as ToolResultMessage);
				}
			}
			pendingToolCalls = [];
			existingToolResultIds = new Set();
		}
		result.push(...heldSystemMessages);
		heldSystemMessages.length = 0;
	};

	for (let i = 0; i < transformed.length; i++) {
		const msg = transformed[i];

		if (msg.role === "assistant") {
			// If we have pending orphaned tool calls from a previous assistant, insert synthetic results now
			closePendingToolCalls();

			// Skip errored/aborted assistant messages entirely.
			// These are incomplete turns that shouldn't be replayed:
			// - May have partial content (reasoning without message, incomplete tool calls)
			// - Replaying them can cause API errors (e.g., OpenAI "reasoning without following item")
			// - The model should retry from the last valid state
			const assistantMsg = msg as AssistantMessage;
			if (assistantMsg.stopReason === "error" || assistantMsg.stopReason === "aborted") {
				continue;
			}

			// Track tool calls from this assistant message
			const toolCalls = assistantMsg.content.filter((b) => b.type === "toolCall") as ToolCall[];
			if (toolCalls.length > 0) {
				pendingToolCalls = toolCalls;
				existingToolResultIds = new Set();
			}

			result.push(msg);
		} else if (msg.role === "toolResult") {
			existingToolResultIds.add(msg.toolCallId);
			result.push(msg);
		} else if (msg.role === "system") {
			if (pendingToolCalls.length > 0) {
				heldSystemMessages.push(msg);
			} else {
				result.push(msg);
			}
		} else if (msg.role === "user") {
			// A new user turn interrupts tool flow - insert synthetic results for orphaned calls
			closePendingToolCalls();
			result.push(msg);
		} else {
			result.push(msg);
		}
	}

	// If the conversation ends with unresolved tool calls, synthesize results now.
	closePendingToolCalls();

	return result;
}
```

### 3.6 OpenAI-compatible auto-detection (verbatim, `openai-completions.ts:1580-1682`)

```ts
/**
 * Auto-detect compatibility settings from provider name and baseUrl.
 * Used as the base when model.compat is not set; explicit model.compat
 * entries override these detected values.
 */
function detectCompat(model: Model<"openai-completions">): ResolvedOpenAICompletionsCompat {
	const provider = model.provider;
	const baseUrl = model.baseUrl;

	const isZai =
		provider === "zai" ||
		provider === "zai-coding-cn" ||
		baseUrl.includes("api.z.ai") ||
		baseUrl.includes("open.bigmodel.cn");
	const isTogether =
		provider === "together" || baseUrl.includes("api.together.ai") || baseUrl.includes("api.together.xyz");
	const isMoonshot = provider === "moonshotai" || provider === "moonshotai-cn" || baseUrl.includes("api.moonshot.");
	const isOpenRouter = provider === "openrouter" || baseUrl.includes("openrouter.ai");
	const isCloudflareWorkersAI = provider === "cloudflare-workers-ai" || baseUrl.includes("api.cloudflare.com");
	const isCloudflareAiGateway = provider === "cloudflare-ai-gateway" || baseUrl.includes("gateway.ai.cloudflare.com");
	const isNvidia = provider === "nvidia" || baseUrl.includes("integrate.api.nvidia.com");
	const isAntLing = provider === "ant-ling" || baseUrl.includes("api.ant-ling.com");
	const isCerebras = provider === "cerebras" || baseUrl.includes("cerebras.ai");
	const isDeepSeek = provider === "deepseek" || baseUrl.toLowerCase().includes("deepseek.com");

	const isNonStandard =
		isNvidia ||
		isCerebras ||
		provider === "xai" ||
		baseUrl.includes("api.x.ai") ||
		isTogether ||
		baseUrl.includes("chutes.ai") ||
		isDeepSeek ||
		isZai ||
		isMoonshot ||
		provider === "opencode" ||
		baseUrl.includes("opencode.ai") ||
		isCloudflareWorkersAI ||
		isCloudflareAiGateway ||
		isAntLing;

	const useMaxTokens =
		baseUrl.includes("chutes.ai") ||
		isDeepSeek ||
		isMoonshot ||
		isCloudflareAiGateway ||
		isTogether ||
		isNvidia ||
		isAntLing ||
		isZai;

	const isGrok = provider === "xai" || baseUrl.includes("api.x.ai");
	const isOpenRouterDeveloperRoleModel =
		isOpenRouter && (model.id.startsWith("anthropic/") || model.id.startsWith("openai/"));
	const cacheControlFormat = provider === "openrouter" && model.id.startsWith("anthropic/") ? "anthropic" : undefined;

	return {
		supportsStore: !isNonStandard,
		supportsDeveloperRole: isOpenRouterDeveloperRoleModel || (!isNonStandard && !isOpenRouter),
		supportsReasoningEffort:
			!isGrok && !isZai && !isMoonshot && !isTogether && !isCloudflareAiGateway && !isNvidia && !isAntLing,
		supportsUsageInStreaming: true,
		supportsFinishReason: true,
		maxTokensField: useMaxTokens ? "max_tokens" : "max_completion_tokens",
		requiresToolResultName: false,
		requiresAssistantAfterToolResult: false,
		requiresThinkingAsText: false,
		requiresReasoningContentOnAssistantMessages: isDeepSeek,
		thinkingFormat: isDeepSeek
			? "deepseek"
			: isZai
				? "zai"
				: isTogether
					? "together"
					: isAntLing
						? "ant-ling"
						: isOpenRouter
							? "openrouter"
							: "openai",
		openRouterRouting: {},
		vercelGatewayRouting: {},
		chatTemplateKwargs: {},
		chatTemplateArgs: {},
		zaiToolStream: false,
		supportsThinkingTokenBudget: false,
		thinkingTokenBudgetField: undefined,
		// OpenAI compatibility alone does not imply strict JSON-schema tool support.
		supportsStrictMode: false,
		supportsOpenAIGrammarTools: false,
		supportsMidConvoSystemMessages: false,
		supportsMidConvoToolAdditions: false,
		cacheControlFormat,
		sendSessionAffinityHeaders: isOpenRouter,
		sessionAffinityFormat: isOpenRouter ? "openrouter" : "openai",
		supportsLongCacheRetention: !(
			isTogether ||
			isCloudflareWorkersAI ||
			isCloudflareAiGateway ||
			isNvidia ||
			isAntLing
		),
	};
}
```

### 3.7 Wire examples

The streams below are **constructed** from the documented wire formats and
Pi's unit-test fixtures (`packages/ai/test/anthropic-sse-parsing.test.ts`,
`packages/ai/test/openai-codex-stream.test.ts`). They were not recorded from
live endpoints (no paid API calls were permitted). They are the fixtures used
by the prototypes in section 5.

Anthropic Messages request (abbreviated illustration of the shape produced by
Pi's `buildParams` and by the R builder; a complete body generated by the R
builder is printed in section 5.5):

```json
{
  "model": "claude-opus-5-5",
  "messages": [
    {"role": "user", "content": [{"type": "text", "text": "mean mpg by cyl?", "cache_control": {"type": "ephemeral"}}]}
  ],
  "max_tokens": 128000,
  "stream": true,
  "system": [{"type": "text", "text": "You are gptr.", "cache_control": {"type": "ephemeral"}}],
  "tools": [{
    "name": "r_eval", "description": "Evaluate R code in the live session",
    "eager_input_streaming": true,
    "input_schema": {"type": "object", "properties": {"code": {"type": "string"}}, "required": ["code"]},
    "cache_control": {"type": "ephemeral"}
  }],
  "thinking": {"type": "adaptive", "display": "summarized"},
  "output_config": {"effort": "high"}
}
```

Headers: `x-api-key`, `anthropic-version: 2023-06-01`,
`content-type: application/json`, optional `anthropic-beta: a,b,c`.
(VERIFIED against Anthropic's raw-HTTP reference bundled with Claude Code,
`curl/examples.md`.)

Anthropic stream fixture `fixtures/anthropic_tool.sse`:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_01XFDUDYJgAACzvnptvVoYEL","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":2140,"cache_creation_input_tokens":1200,"cache_read_input_tokens":18000,"cache_creation":{"ephemeral_5m_input_tokens":1200,"ephemeral_1h_input_tokens":0},"output_tokens":3}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"The user wants the mean of mpg by cyl. "}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"mtcars is already loaded, so I can run R directly."}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqQBCgIYAhIM1gbcDa9GJwZA2b3hGgxBdjrkzLoky3dl1pkiMOYds"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"I'll compute that in your session"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" — café 😀."}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: content_block_start
data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_01T1x1fJ34qAmk2tNTrN7Up6","name":"r_eval","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"code\": \"aggregate(mpg ~ cyl"}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":", data = mtcars, FUN = mean)\\nprint(\\\"done\\\")\", \"capt"}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"ure_plots\": tru"}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"e, \"timeout_s\": 30}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":2}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":187,"output_tokens_details":{"thinking_tokens":61}}}

event: message_stop
data: {"type":"message_stop"}
```

OpenAI Chat Completions stream fixture
`fixtures/openai_completions_tools.sse`:

```
data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[{"index":0,"delta":{"role":"assistant","content":"","refusal":null},"finish_reason":null}],"usage":null}

data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[{"index":0,"delta":{"reasoning_content":"Need two lookups. "},"finish_reason":null}],"usage":null}

data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[{"index":0,"delta":{"content":"Checking both files"},"finish_reason":null}],"usage":null}

data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[{"index":0,"delta":{"content":"."},"finish_reason":null}],"usage":null}

data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_Ab12Cd34Ef56Gh78Ij90KlMn","type":"function","function":{"name":"read","arguments":""}}]},"finish_reason":null}],"usage":null}

data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"pa"}}]},"finish_reason":null}],"usage":null}

data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"th\":\"R/a.R\"}"}}]},"finish_reason":null}],"usage":null}

data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"call_Zy98Xw76Vu54Ts32Rq10PoNm","type":"function","function":{"name":"grep","arguments":"{\"pattern\":"}}]},"finish_reason":null}],"usage":null}

data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"\"TODO\",\"paths\":[\"R\",\"tests\"],\"ignore_case\":false}"}}]},"finish_reason":null}],"usage":null}

data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":null}

data: {"id":"chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG","object":"chat.completion.chunk","created":1759100000,"model":"gpt-5.5-2026-04-23","choices":[],"usage":{"prompt_tokens":1500,"completion_tokens":96,"total_tokens":1596,"prompt_tokens_details":{"cached_tokens":1024},"completion_tokens_details":{"reasoning_tokens":32}}}

data: [DONE]
```

OpenAI Responses stream fixture `fixtures/openai_responses_tool.sse`:

```
event: response.created
data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_0a1b2c3d4e5f","object":"response","status":"in_progress","model":"gpt-5.5","output":[]}}

event: response.output_item.added
data: {"type":"response.output_item.added","sequence_number":2,"output_index":0,"item":{"id":"rs_0a1b2c","type":"reasoning","summary":[]}}

event: response.reasoning_summary_part.added
data: {"type":"response.reasoning_summary_part.added","sequence_number":3,"item_id":"rs_0a1b2c","output_index":0,"summary_index":0,"part":{"type":"summary_text","text":""}}

event: response.reasoning_summary_text.delta
data: {"type":"response.reasoning_summary_text.delta","sequence_number":4,"item_id":"rs_0a1b2c","output_index":0,"summary_index":0,"delta":"**Planning the edit**"}

event: response.reasoning_summary_part.done
data: {"type":"response.reasoning_summary_part.done","sequence_number":5,"item_id":"rs_0a1b2c","output_index":0,"summary_index":0,"part":{"type":"summary_text","text":"**Planning the edit**"}}

event: response.output_item.done
data: {"type":"response.output_item.done","sequence_number":6,"output_index":0,"item":{"id":"rs_0a1b2c","type":"reasoning","encrypted_content":"gAAAAABo2encryptedblob==","summary":[{"type":"summary_text","text":"**Planning the edit**"}]}}

event: response.output_item.added
data: {"type":"response.output_item.added","sequence_number":7,"output_index":1,"item":{"id":"msg_0a1b2c","type":"message","status":"in_progress","role":"assistant","content":[],"phase":"commentary"}}

event: response.content_part.added
data: {"type":"response.content_part.added","sequence_number":8,"item_id":"msg_0a1b2c","output_index":1,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":9,"item_id":"msg_0a1b2c","output_index":1,"content_index":0,"delta":"Editing "}

event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":10,"item_id":"msg_0a1b2c","output_index":1,"content_index":0,"delta":"the file now."}

event: response.output_item.done
data: {"type":"response.output_item.done","sequence_number":11,"output_index":1,"item":{"id":"msg_0a1b2c","type":"message","status":"completed","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"Editing the file now.","annotations":[]}]}}

event: response.output_item.added
data: {"type":"response.output_item.added","sequence_number":12,"output_index":2,"item":{"id":"fc_0a1b2c","type":"function_call","status":"in_progress","call_id":"call_9Zx8Yw7Vu6","name":"edit","arguments":""}}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","sequence_number":13,"item_id":"fc_0a1b2c","output_index":2,"delta":"{\"path\":\"R/a.R\",\"old\":\"x <- 1\","}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","sequence_number":14,"item_id":"fc_0a1b2c","output_index":2,"delta":"\"new\":\"x <- 2\"}"}

event: response.function_call_arguments.done
data: {"type":"response.function_call_arguments.done","sequence_number":15,"item_id":"fc_0a1b2c","output_index":2,"arguments":"{\"path\":\"R/a.R\",\"old\":\"x <- 1\",\"new\":\"x <- 2\"}"}

event: response.output_item.done
data: {"type":"response.output_item.done","sequence_number":16,"output_index":2,"item":{"id":"fc_0a1b2c","type":"function_call","status":"completed","call_id":"call_9Zx8Yw7Vu6","name":"edit","arguments":"{\"path\":\"R/a.R\",\"old\":\"x <- 1\",\"new\":\"x <- 2\"}"}}

event: response.completed
data: {"type":"response.completed","sequence_number":17,"response":{"id":"resp_0a1b2c3d4e5f","object":"response","status":"completed","model":"gpt-5.5","service_tier":"default","usage":{"input_tokens":5200,"input_tokens_details":{"cached_tokens":4096},"output_tokens":140,"output_tokens_details":{"reasoning_tokens":64},"total_tokens":5340}}}
```

Gemini stream fixture `fixtures/google_tool.sse`:

```
data: {"candidates":[{"content":{"parts":[{"text":"**Working out the query**\nI should list files first.","thought":true}],"role":"model"},"index":0}],"usageMetadata":{"promptTokenCount":812,"totalTokenCount":812},"modelVersion":"gemini-3.5-flash","responseId":"k9_XaJ3vGsmWz7IP"}

data: {"candidates":[{"content":{"parts":[{"text":"Let me look at "}],"role":"model"},"index":0}],"usageMetadata":{"promptTokenCount":812,"candidatesTokenCount":5,"totalTokenCount":860,"thoughtsTokenCount":43},"modelVersion":"gemini-3.5-flash","responseId":"k9_XaJ3vGsmWz7IP"}

data: {"candidates":[{"content":{"parts":[{"text":"the directory."},{"functionCall":{"id":"fc_7h2k","name":"find","args":{"pattern":"*.R","sort":"mtime","limit":20}},"thoughtSignature":"CiQBjz1rX3sigAAAAbase64=="}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":812,"cachedContentTokenCount":512,"candidatesTokenCount":31,"totalTokenCount":886,"thoughtsTokenCount":43},"modelVersion":"gemini-3.5-flash","responseId":"k9_XaJ3vGsmWz7IP"}
```

Real catalog entries (fetched from `pi.dev` on 2026-09-29, shape = Pi `Model`):

```json
{"id":"claude-opus-5-5","name":"Claude Opus 5.5","api":"anthropic-messages","provider":"anthropic","baseUrl":"https://api.anthropic.com","reasoning":true,"input":["text","image"],"cost":{"input":4,"output":20,"cacheRead":0.2,"cacheWrite":5},"contextWindow":1000000,"maxTokens":128000,"thinkingLevelMap":{"off":null,"minimal":null,"low":"low","medium":"medium","high":"high","xhigh":"xhigh","max":"max"},"compat":{"supportsMidConvoEffort":true,"supportsMidConvoSystemMessages":true,"supportsMidConvoToolChanges":true,"forceAdaptiveThinking":true,"supportsTemperature":false,"supportsStrictTools":true},"promptCache":{"short":300,"long":3600},"inputLimits":{"maxRequestBytes":33554432,"images":{"maxPerRequest":600,"resize":{"maxWidth":2000,"maxHeight":2000,"maxBytes":4718592,"jpegQuality":80}}},"type":"chat"}
{"id":"claude-haiku-4-5","name":"Claude Haiku 4.5 (latest)","api":"anthropic-messages","provider":"anthropic","baseUrl":"https://api.anthropic.com","reasoning":true,"input":["text","image"],"cost":{"input":1,"output":5,"cacheRead":0.1,"cacheWrite":1.25},"contextWindow":200000,"maxTokens":64000,"compat":{"supportsStrictTools":true},"promptCache":{"short":300,"long":3600},"type":"chat"}
{"id":"gpt-5.5","name":"GPT-5.5","api":"openai-responses","provider":"openai","baseUrl":"https://api.openai.com/v1","reasoning":true,"input":["text","image"],"cost":{"input":5,"output":30,"cacheRead":0.5,"cacheWrite":0,"tiers":[{"inputTokensAbove":272000,"input":10,"output":45,"cacheRead":1,"cacheWrite":0}]},"contextWindow":272000,"maxTokens":128000,"thinkingLevelMap":{"off":"none","minimal":null,"low":"low","medium":"medium","high":"high","xhigh":"xhigh","max":null},"compat":{"supportsStrictMode":true,"supportsOpenAIGrammarTools":true,"supportsAdditionalTools":true,"supportsToolSearch":true,"supportsMidConvoSystemMessages":true},"type":"chat"}
{"id":"gemini-3-flash-preview","name":"Gemini 3 Flash Preview","api":"google-generative-ai","provider":"google","baseUrl":"https://generativelanguage.googleapis.com/v1beta","reasoning":true,"thinkingLevelMap":{"off":null,"minimal":"minimal","low":"low","medium":"medium","high":"high","xhigh":null,"max":null},"input":["text","image"],"cost":{"input":0.5,"output":3,"cacheRead":0.05,"cacheWrite":0},"contextWindow":1048576,"maxTokens":65536,"type":"chat"}
{"id":"llama-3.1-8b-instant","name":"Llama 3.1 8B","api":"openai-completions","provider":"groq","baseUrl":"https://api.groq.com/openai/v1","reasoning":false,"input":["text"],"cost":{"input":0.05,"output":0.08,"cacheRead":0,"cacheWrite":0},"contextWindow":131072,"maxTokens":131072,"compat":{"supportsStrictMode":true},"type":"chat"}
{"type":"classifier","id":"jev-latest","name":"Jev","api":"typesafe-system-one","provider":"typesafe","baseUrl":"https://api.typesafe.ai/v1/","input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":64000}
```

Current model ids listed by that catalog (2026-09-29): Anthropic
`claude-fable-5`, `claude-fable-5-1`, `claude-haiku-4-5`, `claude-opus-4-5`,
`claude-opus-4-6`, `claude-opus-4-7`, `claude-opus-4-8`, `claude-opus-5`,
`claude-opus-5-5`, `claude-sonnet-4-5`, `claude-sonnet-4-6`,
`claude-sonnet-5`, `claude-sonnet-5-5` (+ dated aliases); OpenAI includes
`gpt-5.5`, `gpt-5.5-pro`, `gpt-5.6-luna|sol|terra`, `gpt-6-astra|luna|sol`,
`gpt-6.1-sol`, `o3`, `o4-mini`; Google includes `gemini-2.5-pro`,
`gemini-2.5-flash`, `gemini-3-flash-preview`, `gemini-3.1-pro-preview`,
`gemini-3.5-flash`, `gemini-3.6-flash`, `gemini-3.7-flash`,
`gemini-3.8-flash`; Groq `llama-3.1-8b-instant`, `llama-3.3-70b-versatile`,
`openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `qwen/qwen3.8-27b`.

Custom OpenAI-compatible endpoint in Pi's `models.json`
(`docs/models.md:49-62`):

```json
{
  "providers": {
    "ollama": {
      "baseUrl": "http://localhost:11434/v1",
      "api": "openai-completions",
      "apiKey": "ollama",
      "models": [ { "id": "qwen2.5-coder:7b" } ]
    }
  }
}
```

### 3.8 OAuth constants (verbatim from source)

Anthropic (`packages/ai/src/auth/oauth/anthropic.ts:13-22`):

```ts
const decode = (s: string) => atob(s);
const CLIENT_ID = decode("OWQxYzI1MGEtZTYxYi00NGQ5LTg4ZWQtNTk0NGQxOTYyZjVl");
const AUTHORIZE_URL = "https://claude.ai/oauth/authorize";
const TOKEN_URL = "https://platform.claude.com/v1/oauth/token";
const CALLBACK_HOST = getProviderEnvValue("PI_OAUTH_CALLBACK_HOST") || "127.0.0.1";
const CALLBACK_PORT = 53692;
const CALLBACK_PATH = "/callback";
const REDIRECT_URI = `http://localhost:${CALLBACK_PORT}${CALLBACK_PATH}`;
const SCOPES =
	"org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload";
```

OpenAI Codex legacy (`openai-codex.ts:22-35`):

```ts
const CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
const AUTH_BASE_URL = "https://auth.openai.com";
const AUTHORIZE_URL = `${AUTH_BASE_URL}/oauth/authorize`;
const TOKEN_URL = `${AUTH_BASE_URL}/oauth/token`;
const REDIRECT_URI = "http://localhost:1455/auth/callback";
const DEVICE_USER_CODE_URL = `${AUTH_BASE_URL}/api/accounts/deviceauth/usercode`;
const DEVICE_TOKEN_URL = `${AUTH_BASE_URL}/api/accounts/deviceauth/token`;
const DEVICE_VERIFICATION_URI = `${AUTH_BASE_URL}/codex/device`;
const DEVICE_REDIRECT_URI = `${AUTH_BASE_URL}/deviceauth/callback`;
const DEVICE_CODE_TIMEOUT_SECONDS = 15 * 60;
const OPENAI_CODEX_BROWSER_LOGIN_METHOD = "browser";
const OPENAI_CODEX_DEVICE_CODE_LOGIN_METHOD = "device_code";
const SCOPE = "openid profile email offline_access";
const JWT_CLAIM_PATH = "https://api.openai.com/auth";
```

OpenAI Sign in with ChatGPT (`openai-chatgpt.ts:15-29`):

```ts
// every login registers a new client with this ID; OpenAI returns the issued client ID in the callback
const DYNAMIC_CLIENT_ID = "dynamic_agent_client";
const AGENT_NAME_HINT = "Pi";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const AUTHORIZE_URL = "https://auth.openai.com/api/accounts/authorize";
const TOKEN_URL = "https://auth.openai.com/api/accounts/oauth/token";
const RESOURCE = "https://api.openai.com/v1";
const CALLBACK_HOST = getProviderEnvValue("PI_OAUTH_CALLBACK_HOST") || "127.0.0.1";
const CALLBACK_PORT = 1455;
const CALLBACK_PATH = "/auth/callback";
const REDIRECT_URI = `http://127.0.0.1:${CALLBACK_PORT}${CALLBACK_PATH}`;
const DIRECT_TOKEN_SCOPE = "chatgpt.tokens.use.direct";
const SCOPE = `openid profile email offline_access resource.invoke ${DIRECT_TOKEN_SCOPE}`;
// Refresh this long before the real expiry so a request never starts with a token about to expire.
const EXPIRY_MARGIN_MS = 3 * 60 * 1000;
```

GitHub Copilot (`github-copilot.ts:10-19, 52-87`):

```ts
const decode = (s: string) => atob(s);
const CLIENT_ID = decode("SXYxLmI1MDdhMDhjODdlY2ZlOTg=");

const COPILOT_HEADERS = {
	"User-Agent": "GitHubCopilotChat/0.35.0",
	"Editor-Version": "vscode/1.107.0",
	"Editor-Plugin-Version": "copilot-chat/0.35.0",
	"Copilot-Integration-Id": "vscode-chat",
} as const;
const COPILOT_API_VERSION = "2026-06-01";
function getUrls(domain: string): {
	deviceCodeUrl: string;
	accessTokenUrl: string;
	copilotTokenUrl: string;
} {
	return {
		deviceCodeUrl: `https://${domain}/login/device/code`,
		accessTokenUrl: `https://${domain}/login/oauth/access_token`,
		copilotTokenUrl: `https://api.${domain}/copilot_internal/v2/token`,
	};
}

/**
 * Parse the proxy-ep from a Copilot token and convert to API base URL.
 * Token format: tid=...;exp=...;proxy-ep=proxy.individual.githubcopilot.com;...
 * Returns API URL like https://api.individual.githubcopilot.com
 */
function getBaseUrlFromToken(token: string): string | null {
	const match = token.match(/proxy-ep=([^;]+)/);
	if (!match) return null;
	const proxyHost = match[1];
	// Convert proxy.xxx to api.xxx
	const apiHost = proxyHost.replace(/^proxy\./, "api.");
	return `https://${apiHost}`;
}

function getGitHubCopilotBaseUrl(token?: string, enterpriseDomain?: string): string {
	// If we have a token, extract the base URL from proxy-ep
	if (token) {
		const urlFromToken = getBaseUrlFromToken(token);
		if (urlFromToken) return urlFromToken;
	}
	// Fallback for enterprise or if token parsing fails
	if (enterpriseDomain) return `https://copilot-api.${enterpriseDomain}`;
	return "https://api.individual.githubcopilot.com";
}
```

OpenRouter (`openrouter.ts:19-22`), xAI (`xai.ts:8-14`), Kimi
(`kimi-coding.ts:14-19`), Meta (`meta.ts:19-26`):

```ts
const AUTHORIZE_URL = "https://openrouter.ai/auth";
const TOKEN_URL = "https://openrouter.ai/api/v1/auth/keys";
const LOGIN_TIMEOUT_MS = 5 * 60 * 1000;
const TOKEN_EXCHANGE_TIMEOUT_MS = 30_000;
const XAI_CLIENT_ID = "b1a00492-073a-47ea-816f-4c329264a828";
const XAI_SCOPE = "openid profile email offline_access grok-cli:access api:access";
const XAI_DEVICE_CODE_URL = "https://auth.x.ai/oauth2/device/code";
const XAI_TOKEN_URL = "https://auth.x.ai/oauth2/token";
// Refresh slightly before the reported expiry to avoid using a token that dies mid-request.
const REFRESH_SKEW_MS = 5 * 60 * 1000;
const DEFAULT_TOKEN_LIFETIME_SECONDS = 3600;
const CLIENT_ID = "17e5f671-d194-4dfb-9706-5516cb48c098";
const DEFAULT_OAUTH_HOST = "https://auth.kimi.com";
const DEVICE_CODE_TIMEOUT_SECONDS = 15 * 60;
const DEFAULT_POLL_INTERVAL_SECONDS = 5;
const REQUEST_TIMEOUT_MS = 30 * 1000;
const REFRESH_MAX_RETRIES = 3;
// Muse Code CLI client id.
const CLIENT_ID = "1031625952748946";
const AUTH_HOST = "https://auth.meta.com";
const DEVICE_AUTHORIZATION_URL = `${AUTH_HOST}/oidc/device/authorization/`;
const DEVICE_TOKEN_URL = `${AUTH_HOST}/oidc/device/token/`;
const API_KEY_MINT_URL = "https://api.meta.ai/muse-code/key";
const API_KEY_LIFETIME_MS = 24 * 60 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 30 * 1000;
```

Official "Sign in with ChatGPT" parameters for open-source apps (VERIFIED as
published at https://developers.openai.com/siwc/token-sharing-open-source/sign-in,
`/token-reference`, `/models-and-inference`, `/errors-and-recovery`,
`/preview-limitations` on 2026-09-29. The original text was obtained through a
summarising fetcher; the verifier re-fetched the raw HTML of all six pages the
same day and corrected the "Redirect rule", `redirect_uri` and "Unsupported"
rows below):

| Item | Value |
|---|---|
| Authorize | `https://auth.openai.com/api/accounts/authorize` |
| First sign-in `client_id` | `dynamic_agent_client` (registration entry point; the issued id, for example `oaiapp_...`, comes back in the callback as `client_id` and must be saved) |
| Other authorize parameters | `agent_name_hint=<app name>` (first registration only), `ext_agent_host_id=urn:uuid:<stable per-host uuid>` (required), `response_type=code`, `redirect_uri=http://127.0.0.1:<port>/auth/callback`, `scope=openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`, `resource=https://api.openai.com/v1`, `state`, `nonce`, `code_challenge`, `code_challenge_method=S256`; on re-authorisation optionally `id_token_hint`, `login_hint` |
| Redirect rule | HTTP loopback on `127.0.0.1` ("Do not substitute with `localhost`"). The documentation's example is `http://127.0.0.1:1455/auth/callback`; later sign-ins may use another port, "only the port may vary. Keep the scheme, host, and path unchanged: `/callback` does not match `/auth/callback`". The same URI (including port) must be sent in the authorize request and the code exchange. Pi's `http://127.0.0.1:1455/auth/callback` matches the documented example (corrected by the verifier; the report previously said the documented path was `/callback`) |
| Token | `POST https://auth.openai.com/api/accounts/oauth/token`, form encoded: `grant_type=authorization_code`, `client_id=<issued>`, `code`, `code_verifier`, `redirect_uri`, `resource` |
| Token response | `access_token`, `refresh_token`, `id_token`, `token_type: "Bearer"`, `expires_in: 3600`, `scope`, `earliest_refresh_at` |
| Lifetimes | access 1 hour; refresh 30 days, rotating (each refresh returns a new refresh token) |
| Inference | `POST https://api.openai.com/v1/responses`, `Authorization: Bearer <access token>`, body must have `store: false` and `stream: true`; models from `GET https://api.openai.com/v1/models` |
| Unsupported (verbatim list from `/preview-limitations`) | request fields `background`, `conversation`, `max_output_tokens`, `max_tool_calls`, `metadata`, `moderation`, `multi_agent`, `prompt`, `prompt_cache_retention`, `safety_identifier`, `temperature`, `top_logprobs`, `top_p`, `truncation`, `user`; `previous_response_id` over HTTP (send full history in `input`); explicit `{type:"message", role:"system"}` input items are rejected (use `instructions` or developer messages); hosted tools (image generation, file search, Code Interpreter, native computer use, hosted MCP/connectors, Responses `tool_search`); audio/video input, Files upload API, transcription API. The page also says "Group function/custom tools in namespaces or supply them through `additional_tools` input items" (UNCERTAIN whether a plain top-level `tools` array of functions is rejected) |
| Errors | `subscription_sharing_user_not_eligible` (403), `subscription_sharing_usage_limit_exceeded` (429, do not retry), `subscription_sharing_usage_unavailable` (503, retry), `subscription_sharing_user_unavailable` (503, retry), `subscription_sharing_unsupported_capability` (400), `subscription_sharing_route_not_supported` (403), `subscription_sharing_invalid_user` (401), refresh failures `invalid_grant`, `refresh_token_reused`, ... -> new sign-in |
| Storage guidance | per issued client id + identity, owner-only file permissions (0600) |

### 3.9 Constants and limits collected from the source

| Constant | Value | Source |
|---|---|---|
| Anthropic tool id pattern / length | `[a-zA-Z0-9_-]`, 64 | `anthropic-messages.ts:1216-1218` |
| OpenAI chat tool id length | 40 | `openai-completions.ts:1203-1216` |
| Responses id part length | 64; item ids start with `fc_` | `openai-responses-shared.ts:154-177` |
| Mistral tool id | 9 alphanumerics | `mistral-conversations.ts:28` |
| OpenAI prompt cache key length | 64 | `openai-prompt-cache.ts:1` |
| Responses minimum `max_output_tokens` | 16 | `openai-responses.ts:33` |
| Default thinking budgets | 1024 / 2048 / 8192 / 16384 | `simple-options.ts:54-59` |
| Minimum answer tokens next to a thinking budget | 1024 | `simple-options.ts:52` |
| Context safety margin for `max_tokens` | 4096 tokens | `simple-options.ts:12` |
| Token estimate | 4 chars per token; image = 4800 chars | `utils/estimate.ts:15-16` |
| Max server-requested retry delay | 60,000 ms | `utils/provider-retry.ts:1` |
| Retry backoff | `min(0.5 * 2^n, 8)` s, up to -25% jitter | `utils/provider-retry.ts:65-66` |
| OAuth refresh window | 5 min before expiry; refresh timeout 15 s | `auth/resolve.ts:102-103` |
| Device code default interval / slow_down increment | 5 s / +5 s; minimum 1 s | `auth/oauth/device-code.ts:5-9` |
| Codex device code timeout | 15 min | `openai-codex.ts:31` |
| Catalog refresh interval / attempt timeout | 4 h / 4 s | `remote-catalog-provider.ts:14-15` |
| Provider error body cap | 4000 chars | `utils/error-body.ts:16` |
| Claude Code version string used in stealth mode | `2.1.280` | `anthropic-messages.ts:87` |
| Callback ports | Anthropic 53692; OpenAI 1455; Radius 1456; OpenRouter ephemeral | OAuth files |
| Image resize defaults | 2000 x 2000 px, 4.5 MiB base64, JPEG quality 80 | `docs/models.md:89` |

---

## 4. Recommended design for gptr

### 4.1 Decisions

1. **Implement four wire adapters natively in R**: `anthropic-messages`,
   `openai-responses`, `openai-completions`, `google-generative-ai`. With
   compat flags the third one covers OpenRouter, Ollama, Groq, DeepSeek,
   Together, Cerebras, Hugging Face, llama.cpp, vLLM, LM Studio (REQ-11).
   Skip Bedrock (SigV4 + binary event stream), Vertex (Google ADC), Azure,
   Mistral, Codex WebSocket in v1; users can reach those models through
   OpenRouter or an OpenAI-compatible gateway.
2. **Keep Pi's data model** (plain lists, JSON round-trippable) so sessions,
   hand-off and catalog entries can be ported 1:1; use snake_case field names
   in R.
3. **Events are small lists without the partial message**; the live message is
   read from the stream object. In R an event that embeds the message would
   copy it on every delta.
4. **Own SSE decoder and own incremental partial-JSON parser** (section 5.1,
   5.2). `httr2::resp_stream_sse()` works (tested) but an own decoder is
   needed anyway for fixture replay, for the curl-multi transport and for
   sub-process bridges.
5. **Two transports behind one function**: blocking-free polling over
   `httr2::req_perform_connection(blocking = FALSE)` (default, interruptible)
   and `curl::multi_add(data = ...)` + `curl::multi_run(timeout = ...)` for
   several concurrent streams in one R process (REQ-33). Both verified.
6. **Subscription plans (REQ-12)**:
   - Claude plan: only through the unmodified `claude` CLI
     (`claude -p --output-format stream-json --verbose
     --include-partial-messages`), started with `processx`. The `stream_event`
     lines of that format wrap raw Anthropic streaming events
     (documented jq filter `.event.delta.type == "text_delta"`), so
     `normalizer_anthropic()` can be reused by feeding it the inner event.
     Do **not** port Pi's stealth mode, do not read Claude Code's credential
     store, do not offer "log in with Claude" inside gptr. Note that
     `claude --bare` never reads OAuth credentials, so plan usage requires the
     non-bare mode.
   - ChatGPT plan, option A (native): OpenAI's official open-source
     "Sign in with ChatGPT" flow + the `openai-responses` adapter with the
     ChatGPT restrictions (`store:false`, `stream:true`; omit every field on
     the "Unsupported" row of the table in 3.8 - at least `temperature`,
     `top_p`, `max_output_tokens`, `metadata`, `prompt_cache_retention`,
     `user`, `previous_response_id` - and send the system prompt as
     `instructions` or a `developer` message, never a `system` input item).
     Pure R, no Node.
   - ChatGPT plan, option B (bridge): `codex exec --json` (JSONL events
     `thread.started`, `turn.started`, `item.started|completed`,
     `turn.completed` with `usage`, `turn.failed`, `error`; verified at
     https://learn.chatgpt.com/docs/non-interactive-mode) or `codex app-server`
     (JSON-RPC over stdio). This matches the wording of REQ-12 ("through
     Codex").
   - Do not ship Pi's legacy Codex backend flow (`chatgpt.com/backend-api`
     with the Codex CLI's client id) nor the Copilot flow in v1.
7. **OpenRouter OAuth** (PKCE -> user-controlled API key) is a documented
   public flow and is the friendliest "no key to paste" onboarding; implement
   it in v1 as the reference OAuth provider.
8. **Catalog**: ship a small snapshot generated from models.dev at package
   build time; refresh on explicit request (or opt-in) into
   `tools::R_user_dir("gptr", "cache")` with ETag revalidation. Do not depend
   on `pi.dev` (private service without a published contract).

### 4.2 Data structures (R lists; S3 class tags only)

| Pi (TypeScript) | gptr (R) |
|---|---|
| `Model` | `structure(list(id, name, api, provider, base_url, reasoning, thinking_level_map, input, cost = list(input, output, cache_read, cache_write, tiers), context_window, max_tokens, headers, compat, type = "chat"), class = "gptr_model")` |
| `Context {systemPrompt, messages, tools}` | `list(system_prompt, messages, tools)` |
| `Tool {name, description, parameters}` | `list(name, description, parameters = <JSON schema as R list>, fn = <R function, never serialised>)` |
| `UserMessage` | `list(role = "user", content = <chr or list of blocks>, timestamp)` |
| `AssistantMessage` | `list(role = "assistant", content, api, provider, model, response_id, response_model, usage, stop_reason, raw_stop_reason, error_message, timestamp)` |
| `ToolResultMessage` | `list(role = "tool_result", tool_call_id, tool_name, content, is_error, details, timestamp)` |
| `TextContent` | `list(type = "text", text, text_signature)` |
| `ThinkingContent` | `list(type = "thinking", thinking, thinking_signature, redacted)` |
| `ImageContent` | `list(type = "image", data, mime_type)` |
| `ToolCall` | `list(type = "tool_call", id, name, arguments = <named list>, thought_signature)` |
| `Usage` | `list(input, output, cache_read, cache_write, cache_write_1h, reasoning, total_tokens, cost = list(input, output, cache_read, cache_write, total))` |
| `StopReason` | `"pending" "stop" "length" "toolUse" "error" "aborted"` (keep Pi's strings) |
| event `contentIndex` (0-based) | `content_index` (1-based) |

JSON rules (all verified in 5.2): parse with
`jsonlite::parse_json(x, simplifyVector = FALSE)`; serialise with
`jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)`; empty
objects must be `structure(list(), names = character(0))`; arrays must be
unnamed lists (`list("code")`), never length-1 atomic vectors.
Caveat (verifier, executed with jsonlite 2.0.0): `digits = NA` writes at most
15 significant digits, so a number with 16-17 significant digits is altered
on output even below 2^53 (`4503599627370497` becomes `4.5035996273705e+15`;
millisecond timestamps with 13 digits are safe). Where large integers in tool
arguments or ids must round-trip exactly, parse with `bigint_as_char = TRUE`
(keeps them as strings) or serialise with `digits = I(17)` (exact, but prints
`0.1` as `0.10000000000000001`).

### 4.3 Function signatures

Internal engine (not necessarily exported; `gptr()` is the front door):

```r
# catalog -------------------------------------------------------------------
llm_model(spec, id = NULL)                       # "anthropic/claude-opus-5-5" or (provider, id); bare names via NSE in gptr()
llm_models(provider = NULL, type = "chat", available = FALSE)   # data.frame
catalog_refresh(force = FALSE, source = "https://models.dev/api.json")
catalog_from_models_dev(json, providers = NULL)  # -> list of gptr_model

# providers -------------------------------------------------------------------
provider_register(id, name, base_url, api, env = character(), headers = NULL,
                  compat = NULL, oauth = NULL, models = NULL)
api_register(api, build, normalizer)             # extension point (REQ-29)
provider_openai_compatible(id, base_url, api_key_env = NULL, compat = list(), models = NULL)  # Ollama, vLLM, ...

# requests --------------------------------------------------------------------
llm_stream(model, context, ...,
           reasoning = NULL,                     # "off" "minimal" "low" "medium" "high" "xhigh" "max"
           max_tokens = NULL, temperature = NULL, tool_choice = NULL,
           cache_retention = c("short", "none", "long"), session_id = NULL,
           api_key = NULL, headers = NULL,
           connect_timeout = 30, idle_timeout = 120, max_retries = 2, max_retry_delay = 60,
           on_event = NULL,                      # function(event, stream)
           on_payload = NULL, on_response = NULL)
# returns the final assistant message (list); never throws for provider errors:
# stop_reason "error"/"aborted" + error_message, exactly like Pi.
llm_complete(model, context, ...)                # llm_stream() without on_event
llm_stream_many(requests, on_event = NULL)       # curl multi; list of final messages
llm_classify(model, state, questions, ..., temperature = NULL)   # System 1

# auth ------------------------------------------------------------------------
auth_resolve(provider, api_key = NULL)           # -> list(api_key, headers, base_url, source) or NULL
auth_login(provider, method = c("api_key", "oauth"))
auth_logout(provider)
auth_status()                                    # data.frame(provider, type, source); never prints secrets
```

Adapter contract:

```r
adapter <- list(
  build = function(model, context, options, auth) list(url, headers, body),
  normalizer = function(model, options) list(push, push_parsed, finish, fail, message)
)
```

`push(sse_event)` parses `sse$data`; `push_parsed(event)` takes an already
parsed provider event (needed for the Claude Code bridge). `finish(aborted)`
and `fail(message, aborted)` produce the terminal event. The prototype in
section 5.3 implements `push`, `finish`, `fail` and `message`; `push_parsed`
is a proposed addition (split each `push` into "parse" and "handle").

Differences between the prototype and Pi that an implementer should know:

| Topic | Pi | R prototype |
|---|---|---|
| `partial` on events | live shared object on every event | not on events; `norm$message()` returns the current message |
| Partial tool arguments | re-parsed on every delta | scanned on every delta, parsed only when `message()` is called (cached per length) |
| Final tool arguments | tolerant parse | strict parse first; flag `arguments_incomplete = TRUE` when only the tolerant parse succeeded |
| Partial number `12.` | key dropped | kept as `12` |
| Hash for shortened ids | 53-bit string hash (`utils/hash.ts`) | first 12 hex chars of SHA-256 |
| Mid-conversation system messages, tool additions, grammar tools, deferred responses, Codex WebSocket | supported | not implemented |
| Assistant text join for chat completions | `""` | `""` (same; consider `"\n\n"`) |

### 4.4 Algorithms to port (all prototyped in section 5)

| Algorithm | R function in the prototype | Notes |
|---|---|---|
| SSE decoding | `sse_parser()` | byte oriented, CR/LF/CRLF, BOM, comments, multi-line data, flush at EOF |
| Partial JSON | `partial_json()`, `parse_streaming_json()`, `repair_json()` | incremental scan, lazy parse, strict final parse with `complete` flag |
| Normalisers | `normalizer_anthropic()`, `normalizer_openai_completions()`, `normalizer_openai_responses()`, `normalizer_google()` | same terminal rules as Pi |
| Cost | `calculate_cost()` | tiers + 1h cache writes |
| Hand-off | `transform_messages()` | two passes as in Pi |
| Level clamping | `supported_thinking_levels()`, `clamp_thinking_level()` | upwards first |
| Request builders | `build_anthropic()`, `build_openai_completions()`, `build_openai_responses()`, `build_google()` | structure verified by JSON validation, not against live APIs |
| OAuth | `pkce_generate()`, `oauth_callback_server()`, `parse_authorization_input()`, `oauth_device_poll()`, `oauth_resolve()` | verified against a local mock authorization server |
| Credential store | `credential_store()` | JSON file, mode 0600, mkdir lock, atomic rename |

Tool execution safety rules to add in the agent loop (from Anthropic's
guidance, 2.8): do not run tools of a turn whose `stop_reason` is `length`,
`error` or `aborted`; when the final strict parse fails (`complete = FALSE`)
return an error tool result `{"INVALID_JSON": "<raw>"}` instead of running the
tool; always validate arguments against the tool's JSON schema.

### 4.5 Credential resolution in gptr

Order (first hit wins), mirroring Pi:

1. `api_key =` argument of the call.
2. Stored credential in `file.path(tools::R_user_dir("gptr", "config"),
   "auth.json")` (override directory with env `GPTR_HOME`); OAuth credentials
   pass through `oauth_resolve()`.
3. Project `.gptr/` configuration (provider entry with `api_key = "$ENV_NAME"`
   or `"!command"`; commands only in trusted projects).
4. `.env` file in the working directory or `.gptr/.env` (REQ-13), read with
   `readRenviron()` (verified to parse `KEY=value` and quoted values; it does
   not understand a leading `export`: verifier run shows `export D=4` silently
   sets a variable literally named `export D`, with no warning, so strip
   `export ` first. Note also that `readRenviron()` writes into the process
   environment, which conflicts with section 6 item 6 - parse the file
   yourself if keys must stay out of `Sys.getenv()`).
5. Environment variables from the provider table (2.4).

Optional: if the `keyring` package is installed, store secrets in the OS
credential store and keep only a reference in `auth.json`.

### 4.6 Package choices

| Package | Role | Dependency type |
|---|---|---|
| `httr2` (>= 1.2.0; tested 1.2.2, recommend `>= 1.2.2`) | request building, redaction of secret headers, `req_perform_connection()`, retries, mocking. `req_perform_connection()` exists since 1.0.4 but gained mocking support only in 1.2.0 (httr2 NEWS, #651), and 1.2.2 fixed an error in its network-failure path (#817), which the prototypes exercise (connection refused) | Imports |
| `curl` (>= 6.4.0) | multi interface for concurrent streams; httr2 1.2.2 itself imports `curl (>= 6.4.0)` (tested 7.0.0) | Imports |
| `jsonlite` | JSON | Imports |
| `openssl` | `rand_bytes()`, `sha256()`, base64 for PKCE; already required by httr2 | Imports |
| `rlang`, `cli` | conditions, console UI | Imports |
| `httpuv` | loopback OAuth callback (fallback: paste the redirect URL) | Suggests |
| `later`, `promises` | async API | Suggests |
| `processx` | `claude` / `codex` bridges | Imports if the R tool needs it anyway, else Suggests |
| `keyring` | OS credential store | Suggests |
| `testthat`, `withr` | tests | Suggests |

`ellmer` 0.4.0 (installed) uses the same base (`httr2 (>= 1.2.1)`, `jsonlite`,
`later`, `promises`, `coro`, `S7`), which confirms the stack is CRAN-proven.
gptr should not depend on ellmer: it needs Pi's message model, signatures and
hand-off rules.

---

## 5. Verified R prototypes

Environment: R 4.4.3 (`/usr/local/bin/R`), `Rscript --vanilla`, macOS
(Darwin 25.6.0), packages httr2 1.2.2, curl 7.0.0 (libcurl 8.14.1), jsonlite
2.0.0, openssl 2.3.5, httpuv 1.6.17, callr 3.7.6. `l10n_info()$"UTF-8"` was
`FALSE` in this session (C locale), so the UTF-8 handling below was exercised
in a non-UTF-8 locale; non-ASCII characters therefore print as `<U+00E9>`.
Everything in this section was executed; outputs are copied from the runs.
Nothing here called a paid API.

Verifier note (2026-09-29): every script below was re-extracted from this
report and re-run with `Rscript --vanilla` in the same environment. All pass
and reproduce the shown outputs except timings, random ports/states and
timestamps. Two defects were found and fixed in place: `test_slow_stream.R`
and `test_oauth.R` waited a fixed time (0.4 s / 1 s) for a background server
and failed intermittently under load (3 of 6 and 2 of 6 concurrent runs);
both now wait for readiness and passed 6/6 and 8/8 concurrent runs. Two
fixtures used by `test_normalize.R` were missing from the report and are now
included in 5.3. The "Observed output" blocks of `test_oauth.R` and
`test_slow_stream.R` were condensed by the original author (blank lines and
auto-printed return values removed); the fixed scripts no longer auto-print.

### 5.1 SSE decoder - `R/sse.R`

```r
# Incremental Server-Sent-Events decoder (pure R, byte oriented).
#
# - feed(chunk): chunk is a raw vector (preferred) or character; returns a list
#   of complete events, each list(event = <chr|NULL>, data = <chr>, id = <chr|NULL>).
# - flush(): call at end of stream; returns the trailing event, if any.
#
# Splitting happens on the bytes 0x0A / 0x0D only, which never occur inside a
# UTF-8 multi-byte sequence, so a multi-byte character split across two network
# chunks is reassembled before it is converted to an R string.
sse_parser <- function() {
  buf <- raw(0)
  started <- FALSE
  pending_cr <- FALSE          # previous chunk ended in CR; swallow one leading LF
  ev_name <- NULL
  ev_id <- NULL
  ev_data <- character()
  ev_has_field <- FALSE

  dispatch <- function() {
    if (is.null(ev_name) && length(ev_data) == 0L) {
      ev_has_field <<- FALSE
      return(NULL)
    }
    out <- list(event = ev_name, data = paste(ev_data, collapse = "\n"), id = ev_id)
    ev_name <<- NULL
    ev_data <<- character()
    ev_has_field <<- FALSE
    out
  }

  handle_line <- function(line_raw) {
    if (length(line_raw) == 0L) return(dispatch())
    if (line_raw[[1L]] == as.raw(0x3a)) return(NULL)          # comment / keep-alive
    colon <- which(line_raw == as.raw(0x3a))
    if (length(colon) == 0L) {
      field <- rawToChar(line_raw); value_raw <- raw(0)
    } else {
      field <- rawToChar(line_raw[seq_len(colon[[1L]] - 1L)])
      value_raw <- line_raw[-seq_len(colon[[1L]])]
      if (length(value_raw) > 0L && value_raw[[1L]] == as.raw(0x20)) value_raw <- value_raw[-1L]
    }
    value <- rawToChar(value_raw)
    Encoding(value) <- "UTF-8"
    switch(field,
      event = { ev_name <<- value },
      data  = { ev_data[[length(ev_data) + 1L]] <<- value },
      id    = { if (!grepl("\\x00", value, useBytes = TRUE)) ev_id <<- value },
      NULL
    )
    NULL
  }

  feed <- function(chunk) {
    if (is.character(chunk)) chunk <- charToRaw(enc2utf8(paste(chunk, collapse = "")))
    if (length(chunk) == 0L) return(list())
    if (pending_cr) {
      pending_cr <<- FALSE
      if (chunk[[1L]] == as.raw(0x0a)) chunk <- chunk[-1L]
    }
    buf <<- c(buf, chunk)
    if (!started && length(buf) >= 3L) {
      started <<- TRUE
      if (identical(buf[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) buf <<- buf[-(1:3)]
    }
    out <- list()
    n <- length(buf)
    brk <- which(buf == as.raw(0x0a) | buf == as.raw(0x0d))
    if (length(brk) == 0L) return(out)
    start <- 1L
    k <- 1L
    while (k <= length(brk)) {
      p <- brk[[k]]
      if (p < start) { k <- k + 1L; next }                     # LF of a CRLF pair
      line <- if (p > start) buf[start:(p - 1L)] else raw(0)
      nxt <- p + 1L
      if (buf[[p]] == as.raw(0x0d)) {
        if (p == n) pending_cr <<- TRUE
        else if (buf[[p + 1L]] == as.raw(0x0a)) nxt <- p + 2L
      }
      ev <- handle_line(line)
      if (!is.null(ev)) out[[length(out) + 1L]] <- ev
      start <- nxt
      k <- k + 1L
    }
    buf <<- if (start <= n) buf[start:n] else raw(0)
    out
  }

  flush <- function() {
    out <- list()
    if (length(buf) > 0L) {
      ev <- handle_line(buf)
      buf <<- raw(0)
      if (!is.null(ev)) out[[length(out) + 1L]] <- ev
    }
    ev <- dispatch()
    if (!is.null(ev)) out[[length(out) + 1L]] <- ev
    out
  }

  list(feed = feed, flush = flush)
}

# Convenience: decode a complete SSE body (raw or character) in `chunk_size` byte slices.
sse_decode_all <- function(body, chunk_size = NULL) {
  if (is.character(body)) body <- charToRaw(enc2utf8(paste(body, collapse = "")))
  p <- sse_parser()
  out <- list()
  if (is.null(chunk_size)) {
    out <- p$feed(body)
  } else {
    i <- 1L
    n <- length(body)
    while (i <= n) {
      j <- min(n, i + chunk_size - 1L)
      out <- c(out, p$feed(body[i:j]))
      i <- j + 1L
    }
  }
  c(out, p$flush())
}
```

### 5.2 Incremental partial JSON - `R/partial_json.R`

```r
# Incremental, tolerant parser for streamed (possibly incomplete) JSON.
#
# pj <- partial_json(); pj$push('{"path": "a.R", "con'); pj$value()
#   -> list(path = "a.R")            # incomplete key dropped
# pj$push('tent": "x <- 1\\n'); pj$value()
#   -> list(path = "a.R", content = "x <- 1\n")   # partial string kept
#
# Semantics follow the npm package `partial-json` with Allow.ALL (what Pi uses):
#   * unterminated string VALUE  -> truncated string (dangling escape removed)
#   * unterminated object KEY, key without value, trailing comma -> dropped
#   * partial literal (t, tr, nul, fals ...) -> completed
#   * partial number -> longest valid numeric prefix, else dropped
#   * open containers -> closed
# Scanning is incremental (each byte is inspected once, and only the
# structural bytes are visited by the R loop), parsing is delegated to jsonlite.

.pj_empty_object <- function() structure(list(), names = character(0))

.pj_specials <- as.raw(c(0x22, 0x5c, 0x7b, 0x7d, 0x5b, 0x5d, 0x2c, 0x3a)) # " \ { } [ ] , :
.pj_ws <- as.raw(c(0x20, 0x09, 0x0a, 0x0d))

.pj_complete_scalar <- function(tok) {
  # tok: non-empty character scalar without surrounding whitespace
  for (lit in c("true", "false", "null")) if (startsWith(lit, tok)) return(lit)
  num_re <- "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$"
  while (nzchar(tok)) {
    if (grepl(num_re, tok)) return(tok)
    tok <- substr(tok, 1L, nchar(tok) - 1L)
  }
  NULL
}

# Remove an incomplete escape sequence (or an unpaired high surrogate escape)
# from the end of the raw content of an unterminated JSON string.
.pj_trim_dangling_escape <- function(bytes) {
  repeat {
    n <- length(bytes)
    if (n == 0L) return(bytes)
    from <- max(1L, n - 11L)
    tail_chr <- rawToChar(bytes[from:n])
    # position of the last backslash in the tail window
    bs <- which(bytes[from:n] == as.raw(0x5c))
    if (length(bs) == 0L) return(bytes)
    last_bs <- from + bs[[length(bs)]] - 1L
    # is that backslash itself escaped? count the run of backslashes ending at last_bs
    run <- 0L
    i <- last_bs
    while (i >= 1L && bytes[[i]] == as.raw(0x5c)) { run <- run + 1L; i <- i - 1L }
    if (run %% 2L == 0L) return(bytes)                 # escaped backslash, nothing dangling
    rest <- if (last_bs < n) rawToChar(bytes[(last_bs + 1L):n]) else ""
    if (rest == "") return(bytes[seq_len(last_bs - 1L)])                       # lone "\"
    if (grepl("^u[0-9a-fA-F]{0,3}$", rest)) { bytes <- bytes[seq_len(last_bs - 1L)]; next }
    if (grepl("^u[dD][89abAB][0-9a-fA-F]{2}$", rest)) { bytes <- bytes[seq_len(last_bs - 1L)]; next }
    return(bytes)
  }
}

# Escape raw control characters inside strings and double backslashes that
# start an invalid escape (port of Pi's repairJson()).
repair_json <- function(txt) {
  b <- charToRaw(enc2utf8(txt))
  n <- length(b)
  if (n == 0L) return(txt)
  idx <- which(b == as.raw(0x22) | b == as.raw(0x5c) | b < as.raw(0x20))
  if (length(idx) == 0L) return(txt)
  out <- vector("list", length(idx) * 2L + 1L)
  k <- 0L
  last <- 0L
  in_str <- FALSE
  skip <- 0L
  emit <- function(x) { k <<- k + 1L; out[[k]] <<- x }
  valid_esc <- as.raw(c(0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74, 0x75))
  for (i in idx) {
    if (i <= skip) next
    byte <- b[[i]]
    if (!in_str) {
      if (byte == as.raw(0x22)) in_str <- TRUE
      next
    }
    if (byte == as.raw(0x22)) { in_str <- FALSE; next }
    if (byte == as.raw(0x5c)) {
      nxt <- if (i < n) b[[i + 1L]] else NULL
      ok <- !is.null(nxt) && nxt %in% valid_esc
      if (ok && nxt == as.raw(0x75)) {
        hex <- if (i + 5L <= n) rawToChar(b[(i + 2L):(i + 5L)]) else ""
        ok <- grepl("^[0-9a-fA-F]{4}$", hex)
      }
      if (ok) { skip <- i + 1L; next }
      if (i > last + 0L) emit(b[(last + 1L):i])
      emit(as.raw(0x5c))
      last <- i
      next
    }
    # control character inside a string
    if (i - 1L > last) emit(b[(last + 1L):(i - 1L)])
    esc <- switch(as.character(as.integer(byte)),
      "8" = "\\b", "12" = "\\f", "10" = "\\n", "13" = "\\r", "9" = "\\t",
      sprintf("\\u%04x", as.integer(byte)))
    emit(charToRaw(esc))
    last <- i
  }
  if (last < n) emit(b[(last + 1L):n])
  res <- rawToChar(unlist(out[seq_len(k)]))
  Encoding(res) <- "UTF-8"
  res
}

parse_json_with_repair <- function(txt) {
  tryCatch(
    jsonlite::parse_json(txt, simplifyVector = FALSE),
    error = function(e) {
      fixed <- repair_json(txt)
      if (identical(fixed, txt)) stop(e)
      jsonlite::parse_json(fixed, simplifyVector = FALSE)
    }
  )
}

partial_json <- function() {
  cap <- 1024L
  buf <- raw(cap)
  n <- 0L
  stack <- character()
  expect <- "value"          # value | key_or_end | key | colon | value_or_end | after_value | done
  in_str <- FALSE
  str_is_key <- FALSE
  str_start <- 0L
  esc <- FALSE
  last_safe <- 0L
  tail_start <- 1L
  cache_n <- -1L
  cache_val <- NULL

  scalar_pending <- function(upto) {
    if (!(expect %in% c("value", "value_or_end"))) return(FALSE)
    if (upto < tail_start) return(FALSE)
    any(!(buf[tail_start:upto] %in% .pj_ws))
  }
  value_done <- function(pos) {
    last_safe <<- pos
    expect <<- if (length(stack)) "after_value" else "done"
  }

  push <- function(delta) {
    if (is.character(delta)) delta <- charToRaw(enc2utf8(paste(delta, collapse = "")))
    m <- length(delta)
    if (m == 0L) return(invisible(NULL))
    if (n + m > cap) {
      while (n + m > cap) cap <<- cap * 2L
      nb <- raw(cap)
      if (n > 0L) nb[seq_len(n)] <- buf[seq_len(n)]
      buf <<- nb
    }
    buf[(n + 1L):(n + m)] <<- delta
    base <- n
    n <<- n + m
    sp <- which(delta %in% .pj_specials)
    skip <- 0L
    if (esc) { skip <- 1L; esc <<- FALSE }
    for (r in sp) {
      if (r == skip) next
      b <- delta[[r]]
      pos <- base + r
      if (in_str) {
        if (b == as.raw(0x5c)) {
          if (r == m) esc <<- TRUE else skip <- r + 1L
        } else if (b == as.raw(0x22)) {
          in_str <<- FALSE
          if (str_is_key) expect <<- "colon" else value_done(pos)
          tail_start <<- pos + 1L
        }
        next
      }
      if (expect == "done") next
      if (b == as.raw(0x22)) {
        in_str <<- TRUE
        str_start <<- pos
        str_is_key <<- length(stack) > 0L && stack[[length(stack)]] == "{" &&
          expect %in% c("key_or_end", "key")
      } else if (b == as.raw(0x7b) || b == as.raw(0x5b)) {
        open <- if (b == as.raw(0x7b)) "{" else "["
        stack[[length(stack) + 1L]] <<- open
        expect <<- if (open == "{") "key_or_end" else "value_or_end"
        last_safe <<- pos
        tail_start <<- pos + 1L
      } else if (b == as.raw(0x7d) || b == as.raw(0x5d)) {
        if (length(stack)) stack <<- stack[-length(stack)]
        value_done(pos)
        tail_start <<- pos + 1L
      } else if (b == as.raw(0x2c)) {
        if (scalar_pending(pos - 1L)) last_safe <<- pos - 1L
        expect <<- if (length(stack) && stack[[length(stack)]] == "{") "key" else "value"
        tail_start <<- pos + 1L
      } else if (b == as.raw(0x3a)) {
        expect <<- "value"
        tail_start <<- pos + 1L
      }
    }
    invisible(NULL)
  }

  closers <- function() {
    if (!length(stack)) return(raw(0))
    charToRaw(paste(rev(ifelse(stack == "{", "}", "]")), collapse = ""))
  }

  completed_text <- function() {
    if (n == 0L) return("")
    body <- NULL
    if (in_str) {
      if (str_is_key) {
        body <- if (last_safe > 0L) buf[seq_len(last_safe)] else raw(0)
      } else {
        content <- if (n > str_start) buf[(str_start + 1L):n] else raw(0)
        content <- .pj_trim_dangling_escape(content)
        body <- c(buf[seq_len(str_start)], content, as.raw(0x22))
      }
    } else if (expect %in% c("after_value", "done")) {
      body <- buf[seq_len(if (expect == "done") last_safe else n)]
    } else {
      tok <- if (n >= tail_start) buf[tail_start:n] else raw(0)
      tok <- tok[!(tok %in% .pj_ws)]
      done <- if (length(tok) && expect %in% c("value", "value_or_end")) {
        .pj_complete_scalar(rawToChar(tok))
      } else NULL
      if (!is.null(done)) {
        body <- c(if (tail_start > 1L) buf[seq_len(tail_start - 1L)] else raw(0), charToRaw(done))
      } else {
        body <- if (last_safe > 0L) buf[seq_len(last_safe)] else raw(0)
      }
    }
    if (length(body) == 0L) return("")
    txt <- rawToChar(c(body, closers()))
    Encoding(txt) <- "UTF-8"
    txt
  }

  value <- function() {
    if (cache_n == n) return(cache_val)
    txt <- completed_text()
    val <- if (!nzchar(trimws(txt))) .pj_empty_object() else {
      tryCatch(parse_json_with_repair(txt), error = function(e) .pj_empty_object())
    }
    if (is.null(val)) val <- .pj_empty_object()
    cache_n <<- n
    cache_val <<- val
    val
  }

  text <- function() {
    if (n == 0L) return("")
    txt <- rawToChar(buf[seq_len(n)])
    Encoding(txt) <- "UTF-8"
    txt
  }

  # Strict final parse: complete JSON expected; falls back to repair, then to the
  # tolerant value. `complete` tells the caller whether the JSON was well formed.
  final <- function() {
    txt <- text()
    if (!nzchar(trimws(txt))) return(list(value = .pj_empty_object(), complete = TRUE))
    strict <- tryCatch(parse_json_with_repair(txt), error = function(e) NULL)
    if (!is.null(strict)) return(list(value = strict, complete = TRUE))
    list(value = value(), complete = FALSE)
  }

  list(push = push, value = value, final = final, text = text,
       completed_text = completed_text, size = function() n)
}

# One-shot helper mirroring Pi's parseStreamingJson().
parse_streaming_json <- function(txt) {
  if (is.null(txt) || !nzchar(trimws(txt))) return(.pj_empty_object())
  strict <- tryCatch(parse_json_with_repair(txt), error = function(e) NULL)
  if (!is.null(strict)) return(strict)
  pj <- partial_json()
  pj$push(txt)
  pj$value()
}
```

Test script `test_partial_json.R`:

```r
suppressPackageStartupMessages(library(jsonlite))
source("R/partial_json.R")
source("R/sse.R")

show <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
ok <- 0L; bad <- 0L
check <- function(label, got, want) {
  g <- show(got)
  if (identical(g, want)) { ok <<- ok + 1L; cat(sprintf("  ok   %-42s %s\n", label, g)) }
  else { bad <<- bad + 1L; cat(sprintf("  FAIL %-42s got %s want %s\n", label, g, want)) }
}

cat("== partial JSON: one-shot cases ==\n")
cases <- list(
  list('', '{}'),
  list('{', '{}'),
  list('{"', '{}'),
  list('{"pa', '{}'),
  list('{"path"', '{}'),
  list('{"path":', '{}'),
  list('{"path": ', '{}'),
  list('{"path": "', '{"path":""}'),
  list('{"path": "src/ma', '{"path":"src/ma"}'),
  list('{"path": "src/main.R"', '{"path":"src/main.R"}'),
  list('{"path": "src/main.R",', '{"path":"src/main.R"}'),
  list('{"path": "src/main.R", "con', '{"path":"src/main.R"}'),
  list('{"path": "a", "content": "x <- 1\\', '{"path":"a","content":"x <- 1"}'),
  list('{"path": "a", "content": "x <- 1\\n', '{"path":"a","content":"x <- 1\\n"}'),
  list('{"s": "tab\\there \\"q\\" \\u00e', '{"s":"tab\\there \\"q\\" "}'),
  list('{"s": "emoji \\ud83d', '{"s":"emoji "}'),
  list('{"s": "emoji \\ud83d\\ude', '{"s":"emoji "}'),
  list('{"s": "back\\\\', '{"s":"back\\\\"}'),
  list('{"n": 12', '{"n":12}'),
  list('{"n": 12.', '{"n":12}'),
  list('{"n": 1.5e', '{"n":1.5}'),
  list('{"n": -', '{}'),
  list('{"a": 1, "n": -', '{"a":1}'),
  list('{"b": tr', '{"b":true}'),
  list('{"b": fals', '{"b":false}'),
  list('{"b": nu', '{"b":null}'),
  list('{"xs": [1, 2', '{"xs":[1,2]}'),
  list('{"xs": [1, 2,', '{"xs":[1,2]}'),
  list('{"xs": [{"a": 1}, {"b": "z', '{"xs":[{"a":1},{"b":"z"}]}'),
  list('{"edits": [{"old": "a", "new": "b"}, {"old', '{"edits":[{"old":"a","new":"b"},{}]}'),
  list('{"a": {"b": {"c": [', '{"a":{"b":{"c":[]}}}'),
  list('{"a": "x, y: {z} [w]", "b', '{"a":"x, y: {z} [w]"}'),
  list('{"a": 1}', '{"a":1}'),
  list('{"a": 1} trailing', '{"a":1}'),
  list('[', '[]'),
  list('["a", "b', '["a","b"]')
)
for (cs in cases) check(sprintf("%s", cs[[1]]), parse_streaming_json(cs[[1]]), cs[[2]])

cat("\n== partial JSON: incremental == one-shot for every prefix and every split ==\n")
full <- '{"path": "R/plot.R", "edits": [{"old": "ggplot(df, aes(x, y))", "new": "ggplot(df, aes(x = wt, y = mpg)) +\\n  geom_point(colour = \\"#1b9e77\\")"}, {"old": "caf\u00e9 \\u00e9 \\ud83d\\ude00", "new": null}], "dry_run": false, "limit": 12.5e3}'
bytes <- charToRaw(enc2utf8(full))
mismatch <- 0L
set.seed(1)
for (k in seq_along(bytes)) {
  prefix <- bytes[seq_len(k)]
  # skip prefixes that cut a multi-byte UTF-8 character (cannot occur: deltas are whole strings)
  txt <- rawToChar(prefix); Encoding(txt) <- "UTF-8"
  if (!validUTF8(txt)) next
  one <- show(parse_streaming_json(txt))
  pj <- partial_json()
  cuts <- sort(unique(c(0L, sample.int(k, min(k, 4L)), k)))
  for (j in seq_len(length(cuts) - 1L)) pj$push(prefix[(cuts[j] + 1L):cuts[j + 1L]])
  inc <- show(pj$value())
  if (!identical(one, inc)) { mismatch <- mismatch + 1L; cat("  MISMATCH at", k, one, inc, "\n") }
}
cat(sprintf("  prefixes tested: %d, incremental/one-shot mismatches: %d\n", length(bytes), mismatch))
cat("  final strict parse equals jsonlite: ",
    identical(show(parse_streaming_json(full)), show(jsonlite::parse_json(full))), "\n")
cat("  value at 60%: ", show(parse_streaming_json(rawToChar(bytes[1:120]))), "\n")

cat("\n== repair_json ==\n")
broken <- "{\"cmd\": \"line1\nline2\ttabbed \\d+ C:\\Users\\me\"}"
cat("  input   : ", gsub("\n", "<LF>", gsub("\t", "<TAB>", broken)), "\n")
cat("  repaired: ", repair_json(broken), "\n")
cat("  parsed  : ", show(parse_streaming_json(broken)), "\n")

cat("\n== jsonlite round trip pitfalls ==\n")
args <- jsonlite::parse_json('{"a": [1], "b": [], "c": {}, "d": null, "e": "x", "f": [ "only" ], "g": 9007199254740993}')
cat("  round trip: ", show(args), "\n")
cat("  list()      -> ", show(list()), "   named empty list -> ", show(.pj_empty_object()), "\n")
cat("  character(0)-> ", show(character(0)), "   'a' -> ", show("a"), "   I('a') -> ", show(I("a")), "   list('a') -> ", show(list("a")), "\n")

cat("\n== performance: 200 KB string argument streamed in 2000 deltas ==\n")
big <- paste0('{"path": "big.R", "content": "',
              paste(rep('x <- c(1, 2, 3)\\n  y <- \\"quoted\\" # comment {a: [1]}\\n', 3300), collapse = ""), '"}')
bb <- charToRaw(big)
cat("  bytes:", length(bb), "\n")
cuts <- unique(c(seq(0L, length(bb), length.out = 2001L) |> as.integer(), length(bb)))
t_push <- system.time({
  pj <- partial_json()
  for (j in seq_len(length(cuts) - 1L)) pj$push(bb[(cuts[j] + 1L):cuts[j + 1L]])
})[["elapsed"]]
t_val <- system.time(v <- pj$value())[["elapsed"]]
cat(sprintf("  incremental scan of all deltas: %.3fs; one value() at the end: %.3fs; nchar(content)=%d\n",
            t_push, t_val, nchar(v$content)))
t_each <- system.time({
  pj <- partial_json()
  for (j in seq_len(length(cuts) - 1L)) { pj$push(bb[(cuts[j] + 1L):cuts[j + 1L]]); if (j %% 20L == 0L) pj$value() }
})[["elapsed"]]
cat(sprintf("  scan + value() every 20th delta (100 parses): %.3fs\n", t_each))
t_naive <- system.time({
  acc <- ""
  for (j in seq_len(length(cuts) - 1L)) {
    acc <- paste0(acc, rawToChar(bb[(cuts[j] + 1L):cuts[j + 1L]]))
    if (j %% 20L == 0L) parse_streaming_json(acc)
  }
})[["elapsed"]]
cat(sprintf("  naive re-scan from scratch every 20th delta: %.3fs\n", t_naive))

cat("\n== SSE decoder ==\n")
sse_txt <- paste0(
  ": keep-alive comment\n\n",
  "event: message_start\ndata: {\"a\":1}\n\n",
  "data: line one\ndata: line two\n\n",
  "event: ping\r\ndata: {\"type\": \"ping\"}\r\n\r\n",
  "data:no-space\n\n",
  "event: utf8\ndata: {\"t\":\"caf\u00e9 \U0001F600 \u4e2d\u6587\"}\n\n",
  "data: trailing-without-blank-line")
ref <- sse_decode_all(sse_txt)
str(lapply(ref, function(e) c(event = if (is.null(e$event)) NA else e$event, data = e$data)))
all_same <- TRUE
for (cs in c(1L, 2L, 3L, 5L, 7L, 16L, 64L)) {
  got <- sse_decode_all(sse_txt, chunk_size = cs)
  same <- identical(got, ref)
  all_same <- all_same && same
  cat(sprintf("  chunk_size=%2d -> %d events, identical to unchunked: %s\n", cs, length(got), same))
}
if (all_same) ok <- ok + 1L else bad <- bad + 1L

cat(sprintf("\nSUMMARY: %d ok, %d failed, %d incremental mismatches\n", ok, bad, mismatch))
```

Observed output (`Rscript --vanilla test_partial_json.R`):

```
== partial JSON: one-shot cases ==
  ok                                              {}
  ok   {                                          {}
  ok   {"                                         {}
  ok   {"pa                                       {}
  ok   {"path"                                    {}
  ok   {"path":                                   {}
  ok   {"path":                                   {}
  ok   {"path": "                                 {"path":""}
  ok   {"path": "src/ma                           {"path":"src/ma"}
  ok   {"path": "src/main.R"                      {"path":"src/main.R"}
  ok   {"path": "src/main.R",                     {"path":"src/main.R"}
  ok   {"path": "src/main.R", "con                {"path":"src/main.R"}
  ok   {"path": "a", "content": "x <- 1\          {"path":"a","content":"x <- 1"}
  ok   {"path": "a", "content": "x <- 1\n         {"path":"a","content":"x <- 1\n"}
  ok   {"s": "tab\there \"q\" \u00e               {"s":"tab\there \"q\" "}
  ok   {"s": "emoji \ud83d                        {"s":"emoji "}
  ok   {"s": "emoji \ud83d\ude                    {"s":"emoji "}
  ok   {"s": "back\\                              {"s":"back\\"}
  ok   {"n": 12                                   {"n":12}
  ok   {"n": 12.                                  {"n":12}
  ok   {"n": 1.5e                                 {"n":1.5}
  ok   {"n": -                                    {}
  ok   {"a": 1, "n": -                            {"a":1}
  ok   {"b": tr                                   {"b":true}
  ok   {"b": fals                                 {"b":false}
  ok   {"b": nu                                   {"b":null}
  ok   {"xs": [1, 2                               {"xs":[1,2]}
  ok   {"xs": [1, 2,                              {"xs":[1,2]}
  ok   {"xs": [{"a": 1}, {"b": "z                 {"xs":[{"a":1},{"b":"z"}]}
  ok   {"edits": [{"old": "a", "new": "b"}, {"old {"edits":[{"old":"a","new":"b"},{}]}
  ok   {"a": {"b": {"c": [                        {"a":{"b":{"c":[]}}}
  ok   {"a": "x, y: {z} [w]", "b                  {"a":"x, y: {z} [w]"}
  ok   {"a": 1}                                   {"a":1}
  ok   {"a": 1} trailing                          {"a":1}
  ok   [                                          []
  ok   ["a", "b                                   ["a","b"]

== partial JSON: incremental == one-shot for every prefix and every split ==
  prefixes tested: 232, incremental/one-shot mismatches: 0
  final strict parse equals jsonlite:  TRUE 
  value at 60%:  {"path":"R/plot.R","edits":[{"old":"ggplot(df, aes(x, y))","new":"ggplot(df, aes(x = wt, y = mpg)) +\n  geom_point"}]} 

== repair_json ==
  input   :  {"cmd": "line1<LF>line2<TAB>tabbed \d+ C:\Users\me"} 
  repaired:  {"cmd": "line1\nline2\ttabbed \\d+ C:\\Users\\me"} 
  parsed  :  {"cmd":"line1\nline2\ttabbed \\d+ C:\\Users\\me"} 

== jsonlite round trip pitfalls ==
  round trip:  {"a":[1],"b":[],"c":{},"d":null,"e":"x","f":["only"],"g":9.00719925474099e+15} 
  list()      ->  []    named empty list ->  {} 
  character(0)->  []    'a' ->  "a"    I('a') ->  ["a"]    list('a') ->  ["a"] 

== performance: 200 KB string argument streamed in 2000 deltas ==
  bytes: 181532 
  incremental scan of all deltas: 0.056s; one value() at the end: 0.004s; nchar(content)=168300
  scan + value() every 20th delta (100 parses): 0.452s
  naive re-scan from scratch every 20th delta: 5.767s

== SSE decoder ==
List of 6
 $ : Named chr [1:2] "message_start" "{\"a\":1}"
  ..- attr(*, "names")= chr [1:2] "event" "data"
 $ : Named chr [1:2] NA "line one\nline two"
  ..- attr(*, "names")= chr [1:2] "event" "data"
 $ : Named chr [1:2] "ping" "{\"type\": \"ping\"}"
  ..- attr(*, "names")= chr [1:2] "event" "data"
 $ : Named chr [1:2] NA "no-space"
  ..- attr(*, "names")= chr [1:2] "event" "data"
 $ : Named chr [1:2] "utf8" "{\"t\":\"caf<U+00E9> <U+0001F600> <U+4E2D><U+6587>\"}"
  ..- attr(*, "names")= chr [1:2] "event" "data"
 $ : Named chr [1:2] NA "trailing-without-blank-line"
  ..- attr(*, "names")= chr [1:2] "event" "data"
  chunk_size= 1 -> 6 events, identical to unchunked: TRUE
  chunk_size= 2 -> 6 events, identical to unchunked: TRUE
  chunk_size= 3 -> 6 events, identical to unchunked: TRUE
  chunk_size= 5 -> 6 events, identical to unchunked: TRUE
  chunk_size= 7 -> 6 events, identical to unchunked: TRUE
  chunk_size=16 -> 6 events, identical to unchunked: TRUE
  chunk_size=64 -> 6 events, identical to unchunked: TRUE

SUMMARY: 37 ok, 0 failed, 0 incremental mismatches
```

### 5.3 Normalisers - `R/normalize.R`

```r
# Normalisers: provider wire events -> gptr stream events.
#
# Every normaliser is a closure with
#   $push(sse)   sse = list(event=, data=) from sse_parser(); returns list of events
#   $finish(aborted = FALSE)   end of HTTP body; returns the terminal event(s)
#   $fail(msg, aborted = FALSE) transport/HTTP error; returns the terminal error event
#   $message()   the live assistant message (the "partial")
#
# Events are small lists: list(type=, content_index=, delta=, ...). They do NOT
# embed the partial message (R would copy it per event); ask $message() instead.
# content_index is 1-based.

`%||%` <- function(a, b) if (is.null(a)) b else a

usage_zero <- function() {
  list(input = 0, output = 0, cache_read = 0, cache_write = 0, total_tokens = 0,
       cost = list(input = 0, output = 0, cache_read = 0, cache_write = 0, total = 0))
}

# Port of Pi calculateCost(): rates are USD per million tokens; tiers switch the
# whole request to the highest matching `input_tokens_above` tier; Anthropic 1h
# cache writes are billed at 2x base input.
calculate_cost <- function(model, usage) {
  rates <- model$cost
  input_tokens <- usage$input + usage$cache_read + usage$cache_write
  matched <- -1
  for (tier in model$cost$tiers %||% list()) {
    if (input_tokens > tier$input_tokens_above && tier$input_tokens_above > matched) {
      rates <- tier
      matched <- tier$input_tokens_above
    }
  }
  long_write <- usage$cache_write_1h %||% 0
  short_write <- usage$cache_write - long_write
  cost <- list(
    input = rates$input / 1e6 * usage$input,
    output = rates$output / 1e6 * usage$output,
    cache_read = rates$cache_read / 1e6 * usage$cache_read,
    cache_write = (rates$cache_write * short_write + rates$input * 2 * long_write) / 1e6
  )
  cost$total <- cost$input + cost$output + cost$cache_read + cost$cache_write
  usage$cost <- cost
  usage
}

new_assistant_message <- function(model) {
  list(role = "assistant", content = list(), api = model$api, provider = model$provider,
       model = model$id, usage = usage_zero(), stop_reason = "pending",
       timestamp = round(as.numeric(Sys.time()) * 1000))
}

.parse_data <- function(sse) jsonlite::parse_json(sse$data, simplifyVector = FALSE)

# Shared scaffolding -----------------------------------------------------------
.normalizer_core <- function(model) {
  self <- new.env(parent = emptyenv())
  self$msg <- new_assistant_message(model)
  self$started <- FALSE
  self$terminated <- FALSE
  self$pj <- list()                # content_index -> partial_json accumulator

  self$ev <- function(type, ...) list(type = type, ...)
  self$start <- function() {
    if (self$started) return(list())
    self$started <- TRUE
    list(self$ev("start"))
  }
  self$add_block <- function(block) {
    i <- length(self$msg$content) + 1L
    self$msg$content[[i]] <- block
    i
  }
  self$tool_args <- function(i) {
    acc <- self$pj[[as.character(i)]]
    if (is.null(acc)) structure(list(), names = character(0)) else acc$value()
  }
  self$finalize_tool <- function(i) {
    acc <- self$pj[[as.character(i)]]
    if (!is.null(acc)) {
      fin <- acc$final()
      self$msg$content[[i]]$arguments <- fin$value
      if (!isTRUE(fin$complete)) self$msg$content[[i]]$arguments_incomplete <- TRUE
      self$pj[[as.character(i)]] <- NULL
    }
    self$msg$content[[i]]
  }
  self$message <- function() {
    # materialise lazily parsed partial tool arguments
    m <- self$msg
    for (k in names(self$pj)) {
      i <- as.integer(k)
      m$content[[i]]$arguments <- self$pj[[k]]$value()
    }
    m
  }
  self$done <- function() {
    self$terminated <- TRUE
    list(self$ev("done", reason = self$msg$stop_reason, message = self$message()))
  }
  self$fail <- function(msg, aborted = FALSE) {
    if (self$terminated) return(list())
    self$terminated <- TRUE
    self$msg$stop_reason <- if (aborted) "aborted" else "error"
    self$msg$error_message <- msg
    # keep the best-effort partial arguments, drop the scratch buffers
    self$msg <- self$message()
    self$pj <- list()
    list(self$ev("error", reason = self$msg$stop_reason, error = self$msg))
  }
  self
}

# ---------------------------------------------------------------------------
# Anthropic Messages API (POST {base}/v1/messages, stream: true)
# ---------------------------------------------------------------------------
normalizer_anthropic <- function(model) {
  s <- .normalizer_core(model)
  index_map <- list()              # wire index (chr) -> content_index
  saw_start <- FALSE; saw_stop <- FALSE
  wire_events <- c("message_start", "message_delta", "message_stop",
                   "content_block_start", "content_block_delta", "content_block_stop")

  map_stop <- function(reason, details = NULL) {
    switch(reason,
      end_turn = list("stop"), max_tokens = list("length"), tool_use = list("toolUse"),
      pause_turn = list("stop"), stop_sequence = list("stop"),
      refusal = list("error", details$explanation %||% "The model refused to complete the request"),
      sensitive = list("error", "Provider stopped with: sensitive"),
      list("error", paste0("Unhandled stop reason: ", reason)))
  }
  recompute <- function() {
    u <- s$msg$usage
    u$total_tokens <- u$input + u$output + u$cache_read + u$cache_write
    s$msg$usage <- calculate_cost(model, u)
  }

  push <- function(sse) {
    if (s$terminated) return(list())
    name <- sse$event %||% ""
    if (identical(name, "error")) return(s$fail(sse$data))
    if (!(name %in% wire_events)) return(list())          # ping and unknown events
    e <- tryCatch(parse_json_with_repair(sse$data), error = function(err) NULL)
    if (is.null(e)) return(s$fail(paste0("Could not parse Anthropic SSE event ", name, ": ", sse$data)))
    out <- s$start()
    type <- e$type
    if (type == "message_start") {
      saw_start <<- TRUE
      m <- e$message
      s$msg$response_id <- m$id
      if (!is.null(m$model) && !identical(m$model, model$id)) s$msg$response_model <- m$model
      u <- m$usage %||% list()
      s$msg$usage$input <- u$input_tokens %||% 0
      s$msg$usage$output <- u$output_tokens %||% 0
      s$msg$usage$cache_read <- u$cache_read_input_tokens %||% 0
      s$msg$usage$cache_write <- u$cache_creation_input_tokens %||% 0
      s$msg$usage$cache_write_1h <- u$cache_creation$ephemeral_1h_input_tokens %||% 0
      recompute()
    } else if (type == "content_block_start") {
      cb <- e$content_block
      key <- as.character(e$index)
      if (cb$type == "text") {
        i <- s$add_block(list(type = "text", text = cb$text %||% ""))
        index_map[[key]] <<- i
        out <- c(out, list(s$ev("text_start", content_index = i)))
      } else if (cb$type == "thinking") {
        i <- s$add_block(list(type = "thinking", thinking = cb$thinking %||% "",
                              thinking_signature = cb$signature %||% ""))
        index_map[[key]] <<- i
        out <- c(out, list(s$ev("thinking_start", content_index = i)))
      } else if (cb$type == "redacted_thinking") {
        i <- s$add_block(list(type = "thinking", thinking = "[Reasoning redacted]",
                              thinking_signature = cb$data, redacted = TRUE))
        index_map[[key]] <<- i
        out <- c(out, list(s$ev("thinking_start", content_index = i)))
      } else if (cb$type == "tool_use") {
        i <- s$add_block(list(type = "tool_call", id = cb$id, name = cb$name,
                              arguments = structure(list(), names = character(0))))
        index_map[[key]] <<- i
        s$pj[[as.character(i)]] <- partial_json()
        out <- c(out, list(s$ev("toolcall_start", content_index = i)))
      }
    } else if (type == "content_block_delta") {
      i <- index_map[[as.character(e$index)]]
      if (is.null(i)) return(out)
      d <- e$delta
      kind <- s$msg$content[[i]]$type
      if (d$type == "text_delta" && kind == "text") {
        s$msg$content[[i]]$text <- paste0(s$msg$content[[i]]$text, d$text)
        out <- c(out, list(s$ev("text_delta", content_index = i, delta = d$text)))
      } else if (d$type == "thinking_delta" && kind == "thinking") {
        s$msg$content[[i]]$thinking <- paste0(s$msg$content[[i]]$thinking, d$thinking)
        out <- c(out, list(s$ev("thinking_delta", content_index = i, delta = d$thinking)))
      } else if (d$type == "input_json_delta" && kind == "tool_call") {
        s$pj[[as.character(i)]]$push(d$partial_json)
        out <- c(out, list(s$ev("toolcall_delta", content_index = i, delta = d$partial_json)))
      } else if (d$type == "signature_delta" && kind == "thinking") {
        s$msg$content[[i]]$thinking_signature <-
          paste0(s$msg$content[[i]]$thinking_signature %||% "", d$signature)
      }
    } else if (type == "content_block_stop") {
      i <- index_map[[as.character(e$index)]]
      if (is.null(i)) return(out)
      b <- s$msg$content[[i]]
      if (b$type == "text") out <- c(out, list(s$ev("text_end", content_index = i, content = b$text)))
      else if (b$type == "thinking") out <- c(out, list(s$ev("thinking_end", content_index = i, content = b$thinking)))
      else if (b$type == "tool_call") out <- c(out, list(s$ev("toolcall_end", content_index = i, tool_call = s$finalize_tool(i))))
    } else if (type == "message_delta") {
      if (!is.null(e$delta$stop_reason)) {
        s$msg$raw_stop_reason <- e$delta$stop_reason
        m <- map_stop(e$delta$stop_reason, e$delta$stop_details)
        s$msg$stop_reason <- m[[1]]
        if (length(m) > 1L) s$msg$error_message <- m[[2]]
      }
      u <- e$usage
      if (!is.null(u)) {
        if (!is.null(u$input_tokens)) s$msg$usage$input <- u$input_tokens
        if (!is.null(u$output_tokens)) s$msg$usage$output <- u$output_tokens
        if (!is.null(u$cache_read_input_tokens)) s$msg$usage$cache_read <- u$cache_read_input_tokens
        if (!is.null(u$cache_creation_input_tokens)) s$msg$usage$cache_write <- u$cache_creation_input_tokens
        if (!is.null(u$cache_creation$ephemeral_1h_input_tokens)) s$msg$usage$cache_write_1h <- u$cache_creation$ephemeral_1h_input_tokens
        if (!is.null(u$output_tokens_details$thinking_tokens)) s$msg$usage$reasoning <- u$output_tokens_details$thinking_tokens
      }
      recompute()
    } else if (type == "message_stop") {
      saw_stop <<- TRUE
    }
    out
  }

  finish <- function(aborted = FALSE) {
    if (s$terminated) return(list())
    if (aborted) return(s$fail("Request was aborted", aborted = TRUE))
    if (saw_start && !saw_stop) return(s$fail("Anthropic stream ended before message_stop"))
    if (s$msg$stop_reason == "pending") return(s$fail("Anthropic stream ended without a stop reason"))
    if (s$msg$stop_reason %in% c("error", "aborted")) return(s$fail(s$msg$error_message %||% "An unknown error occurred"))
    s$done()
  }
  list(push = push, finish = finish, fail = s$fail, message = s$message)
}

# ---------------------------------------------------------------------------
# OpenAI Chat Completions (POST {base}/chat/completions, stream: true)
# ---------------------------------------------------------------------------
normalizer_openai_completions <- function(model, supports_finish_reason = TRUE) {
  s <- .normalizer_core(model)
  text_i <- NULL; think_i <- NULL
  by_index <- list(); by_id <- list()
  has_finish <- FALSE
  saw_done <- FALSE

  map_stop <- function(r) {
    switch(r,
      stop = , end = list("stop"), length = list("length"),
      function_call = , tool_calls = list("toolUse"),
      list("error", paste0("Provider finish_reason: ", r)))
  }
  parse_usage <- function(u) {
    prompt <- u$prompt_tokens %||% 0
    cache_read <- u$prompt_tokens_details$cached_tokens %||% u$prompt_cache_hit_tokens %||% u$cached_tokens %||% 0
    cache_write <- u$prompt_tokens_details$cache_write_tokens %||% 0
    input <- max(0, prompt - cache_read - cache_write)
    output <- u$completion_tokens %||% 0
    calculate_cost(model, list(input = input, output = output, cache_read = cache_read,
      cache_write = cache_write, reasoning = u$completion_tokens_details$reasoning_tokens %||% 0,
      total_tokens = input + output + cache_read + cache_write, cost = usage_zero()$cost))
  }

  push <- function(sse) {
    if (s$terminated) return(list())
    if (identical(trimws(sse$data), "[DONE]")) { saw_done <<- TRUE; return(list()) }
    if (!nzchar(sse$data)) return(list())
    ch <- tryCatch(parse_json_with_repair(sse$data), error = function(err) NULL)
    if (is.null(ch)) return(s$fail(paste0("Invalid chat completion chunk: ", sse$data)))
    if (!is.null(ch$error)) return(s$fail(ch$error$message %||% jsonlite::toJSON(ch$error, auto_unbox = TRUE)))
    out <- s$start()
    if (is.null(s$msg$response_id) && !is.null(ch$id)) s$msg$response_id <- ch$id
    if (is.character(ch$model) && nzchar(ch$model) && !identical(ch$model, model$id) && is.null(s$msg$response_model)) s$msg$response_model <- ch$model
    if (!is.null(ch$usage)) s$msg$usage <- parse_usage(ch$usage)
    choice <- if (length(ch$choices)) ch$choices[[1]] else NULL
    if (is.null(choice)) return(out)
    if (is.null(ch$usage) && !is.null(choice$usage)) s$msg$usage <- parse_usage(choice$usage)
    if (!is.null(choice$finish_reason)) {
      s$msg$raw_stop_reason <- choice$finish_reason
      m <- map_stop(choice$finish_reason)
      s$msg$stop_reason <- m[[1]]
      if (length(m) > 1L) s$msg$error_message <- m[[2]]
      has_finish <<- TRUE
    }
    d <- choice$delta
    if (is.null(d)) return(out)
    if (is.character(d$content) && nzchar(d$content)) {
      if (is.null(text_i)) {
        text_i <<- s$add_block(list(type = "text", text = ""))
        out <- c(out, list(s$ev("text_start", content_index = text_i)))
      }
      s$msg$content[[text_i]]$text <- paste0(s$msg$content[[text_i]]$text, d$content)
      out <- c(out, list(s$ev("text_delta", content_index = text_i, delta = d$content)))
    }
    for (field in c("reasoning_content", "reasoning", "reasoning_text")) {
      v <- d[[field]]
      if (is.character(v) && nzchar(v)) {
        if (is.null(think_i)) {
          think_i <<- s$add_block(list(type = "thinking", thinking = "", thinking_signature = field))
          out <- c(out, list(s$ev("thinking_start", content_index = think_i)))
        }
        s$msg$content[[think_i]]$thinking <- paste0(s$msg$content[[think_i]]$thinking, v)
        out <- c(out, list(s$ev("thinking_delta", content_index = think_i, delta = v)))
        break                                    # first non-empty field wins (avoid duplicates)
      }
    }
    for (tc in d$tool_calls %||% list()) {
      idx <- if (is.numeric(tc$index)) as.character(tc$index) else NULL
      i <- if (!is.null(idx)) by_index[[idx]] else NULL
      if (is.null(i) && is.character(tc$id) && nzchar(tc$id)) i <- by_id[[tc$id]]
      if (is.null(i)) {
        i <- s$add_block(list(type = "tool_call", id = tc$id %||% "", name = tc[["function"]]$name %||% "",
                              arguments = structure(list(), names = character(0))))
        s$pj[[as.character(i)]] <- partial_json()
        out <- c(out, list(s$ev("toolcall_start", content_index = i)))
      }
      if (!is.null(idx)) by_index[[idx]] <<- i
      if (is.character(tc$id) && nzchar(tc$id)) {
        by_id[[tc$id]] <<- i
        if (!nzchar(s$msg$content[[i]]$id)) s$msg$content[[i]]$id <- tc$id
      }
      nm <- tc[["function"]]$name
      if (!nzchar(s$msg$content[[i]]$name) && is.character(nm) && nzchar(nm)) s$msg$content[[i]]$name <- nm
      a <- tc[["function"]]$arguments
      delta <- ""
      if (is.character(a) && nzchar(a)) { delta <- a; s$pj[[as.character(i)]]$push(a) }
      out <- c(out, list(s$ev("toolcall_delta", content_index = i, delta = delta)))
    }
    out
  }

  finish <- function(aborted = FALSE) {
    if (s$terminated) return(list())
    out <- list()
    for (i in seq_along(s$msg$content)) {
      b <- s$msg$content[[i]]
      if (b$type == "text") out <- c(out, list(s$ev("text_end", content_index = i, content = b$text)))
      else if (b$type == "thinking") out <- c(out, list(s$ev("thinking_end", content_index = i, content = b$thinking)))
      else out <- c(out, list(s$ev("toolcall_end", content_index = i, tool_call = s$finalize_tool(i))))
    }
    if (aborted) return(c(out, s$fail("Request was aborted", aborted = TRUE)))
    if (!has_finish && !supports_finish_reason) {
      has_tool <- any(vapply(s$msg$content, function(b) b$type == "tool_call", logical(1)))
      s$msg$stop_reason <- if (has_tool) "toolUse" else "stop"
    }
    if (s$msg$stop_reason == "error") return(c(out, s$fail(s$msg$error_message %||% "Provider returned an error stop reason")))
    if ((supports_finish_reason && !has_finish) || s$msg$stop_reason == "pending") return(c(out, s$fail("Stream ended without finish_reason")))
    c(out, s$done())
  }
  list(push = push, finish = finish, fail = s$fail, message = s$message)
}

# ---------------------------------------------------------------------------
# OpenAI Responses (POST {base}/responses, stream: true) -- also used for
# the Codex backend (type "response.done" is normalised to response.completed).
# ---------------------------------------------------------------------------
normalizer_openai_responses <- function(model) {
  s <- .normalizer_core(model)
  slots <- list()                  # output_index (chr) -> list(kind=, i=)
  saw_terminal <- FALSE

  map_status <- function(status, reason = NULL) {
    if (is.null(status)) return(list("stop"))
    switch(status,
      completed = list("stop"),
      incomplete = if (identical(reason, "max_output_tokens")) list("length") else
        list("error", if (!is.null(reason)) paste0("Response incomplete: ", reason) else "Response incomplete without a provider reason"),
      failed = , cancelled = list("error"),
      in_progress = , queued = list("stop"),
      list("error", paste0("Unhandled stop reason: ", status)))
  }
  slot <- function(e, kind) {
    sl <- slots[[as.character(e$output_index)]]
    if (!is.null(sl) && sl$kind == kind) sl else NULL
  }
  create_slot <- function(output_index, item) {
    key <- as.character(output_index)
    if (item$type == "reasoning") {
      i <- s$add_block(list(type = "thinking", thinking = ""))
      slots[[key]] <<- list(kind = "thinking", i = i)
      return(list(s$ev("thinking_start", content_index = i)))
    }
    if (item$type == "message") {
      if (identical(item$phase, "final_answer")) s$msg$stop_reason <- "stop"
      i <- s$add_block(list(type = "text", text = ""))
      slots[[key]] <<- list(kind = "text", i = i)
      return(list(s$ev("text_start", content_index = i)))
    }
    if (item$type == "function_call") {
      i <- s$add_block(list(type = "tool_call", id = paste0(item$call_id, "|", item$id), name = item$name,
                            arguments = structure(list(), names = character(0))))
      acc <- partial_json()
      if (is.character(item$arguments) && nzchar(item$arguments)) acc$push(item$arguments)
      s$pj[[as.character(i)]] <- acc
      slots[[key]] <<- list(kind = "tool_call", i = i)
      return(list(s$ev("toolcall_start", content_index = i)))
    }
    list()
  }

  push <- function(sse) {
    if (s$terminated || saw_terminal) return(list())
    if (!nzchar(sse$data) || identical(trimws(sse$data), "[DONE]")) return(list())
    e <- tryCatch(parse_json_with_repair(sse$data), error = function(err) NULL)
    if (is.null(e)) return(s$fail(paste0("Invalid Responses SSE JSON: ", sse$data)))
    type <- e$type %||% ""
    out <- s$start()
    if (type == "response.created") {
      s$msg$response_id <- e$response$id
    } else if (type == "response.output_item.added") {
      out <- c(out, create_slot(e$output_index, e$item))
    } else if (type %in% c("response.reasoning_summary_text.delta", "response.reasoning_text.delta")) {
      sl <- slot(e, "thinking"); if (is.null(sl)) return(out)
      s$msg$content[[sl$i]]$thinking <- paste0(s$msg$content[[sl$i]]$thinking, e$delta)
      out <- c(out, list(s$ev("thinking_delta", content_index = sl$i, delta = e$delta)))
    } else if (type == "response.reasoning_summary_part.done") {
      sl <- slot(e, "thinking"); if (is.null(sl)) return(out)
      s$msg$content[[sl$i]]$thinking <- paste0(s$msg$content[[sl$i]]$thinking, "\n\n")
      out <- c(out, list(s$ev("thinking_delta", content_index = sl$i, delta = "\n\n")))
    } else if (type %in% c("response.output_text.delta", "response.refusal.delta")) {
      sl <- slot(e, "text"); if (is.null(sl)) return(out)
      s$msg$content[[sl$i]]$text <- paste0(s$msg$content[[sl$i]]$text, e$delta)
      out <- c(out, list(s$ev("text_delta", content_index = sl$i, delta = e$delta)))
    } else if (type == "response.function_call_arguments.delta") {
      sl <- slot(e, "tool_call"); if (is.null(sl)) return(out)
      s$pj[[as.character(sl$i)]]$push(e$delta)
      out <- c(out, list(s$ev("toolcall_delta", content_index = sl$i, delta = e$delta)))
    } else if (type == "response.function_call_arguments.done") {
      sl <- slot(e, "tool_call"); if (is.null(sl)) return(out)
      prev <- s$pj[[as.character(sl$i)]]$text()
      acc <- partial_json(); acc$push(e$arguments)
      s$pj[[as.character(sl$i)]] <- acc
      if (startsWith(e$arguments, prev) && nchar(e$arguments) > nchar(prev)) {
        out <- c(out, list(s$ev("toolcall_delta", content_index = sl$i, delta = substring(e$arguments, nchar(prev) + 1L))))
      }
    } else if (type == "response.output_item.done") {
      item <- e$item
      key <- as.character(e$output_index)
      if (is.null(slots[[key]])) out <- c(out, create_slot(e$output_index, item))
      sl <- slots[[key]]
      if (is.null(sl)) return(out)
      if (item$type == "reasoning" && sl$kind == "thinking") {
        summary <- paste(vapply(item$summary %||% list(), function(x) x$text %||% "", ""), collapse = "\n\n")
        content <- paste(vapply(item$content %||% list(), function(x) x$text %||% "", ""), collapse = "\n\n")
        txt <- if (nzchar(summary)) summary else if (nzchar(content)) content else s$msg$content[[sl$i]]$thinking
        s$msg$content[[sl$i]]$thinking <- txt
        # the whole reasoning item (incl. encrypted_content) is the replay signature
        s$msg$content[[sl$i]]$thinking_signature <- as.character(jsonlite::toJSON(item, auto_unbox = TRUE, null = "null", digits = NA))
        out <- c(out, list(s$ev("thinking_end", content_index = sl$i, content = txt)))
        slots[[key]] <<- NULL
      } else if (item$type == "message" && sl$kind == "text") {
        if (identical(item$phase, "final_answer")) s$msg$stop_reason <- "stop"
        txt <- paste(vapply(item$content %||% list(), function(x) (if (identical(x$type, "output_text")) x$text else x$refusal) %||% "", ""), collapse = "")
        s$msg$content[[sl$i]]$text <- txt
        sig <- list(v = 1L, id = item$id); if (!is.null(item$phase)) sig$phase <- item$phase
        s$msg$content[[sl$i]]$text_signature <- as.character(jsonlite::toJSON(sig, auto_unbox = TRUE))
        out <- c(out, list(s$ev("text_end", content_index = sl$i, content = txt)))
        slots[[key]] <<- NULL
      } else if (item$type == "function_call" && sl$kind == "tool_call") {
        if (is.character(item$arguments) && nzchar(item$arguments)) {
          acc <- partial_json(); acc$push(item$arguments); s$pj[[as.character(sl$i)]] <- acc
        }
        out <- c(out, list(s$ev("toolcall_end", content_index = sl$i, tool_call = s$finalize_tool(sl$i))))
        slots[[key]] <<- NULL
      }
    } else if (type %in% c("response.completed", "response.incomplete", "response.done")) {
      saw_terminal <<- TRUE
      r <- e$response
      if (!is.null(r$id)) s$msg$response_id <- r$id
      if (!is.null(r$usage)) {
        cached <- r$usage$input_tokens_details$cached_tokens %||% 0
        cwrite <- r$usage$input_tokens_details$cache_write_tokens %||% 0
        s$msg$usage <- list(input = max(0, (r$usage$input_tokens %||% 0) - cached - cwrite),
          output = r$usage$output_tokens %||% 0, cache_read = cached, cache_write = cwrite,
          reasoning = r$usage$output_tokens_details$reasoning_tokens %||% 0,
          total_tokens = r$usage$total_tokens %||% 0, cost = usage_zero()$cost)
      }
      s$msg$usage <- calculate_cost(model, s$msg$usage)
      reason <- r$incomplete_details$reason
      s$msg$raw_stop_reason <- if (!is.null(reason)) paste0(r$status, ".", reason) else r$status
      m <- map_status(r$status, reason)
      s$msg$stop_reason <- m[[1]]
      s$msg$error_message <- if (length(m) > 1L) m[[2]] else NULL
      has_tool <- any(vapply(s$msg$content, function(b) b$type == "tool_call", logical(1)))
      if (has_tool && s$msg$stop_reason == "stop") s$msg$stop_reason <- "toolUse"
    } else if (type == "error") {
      return(c(out, s$fail(sprintf("Error Code %s: %s", e$code %||% e$error$code %||% "unknown", e$message %||% e$error$message %||% "Unknown error"))))
    } else if (type == "response.failed") {
      err <- e$response$error
      msg <- if (!is.null(err)) sprintf("%s: %s", err$code %||% "unknown", err$message %||% "no message") else "Unknown error (no error details in response)"
      return(c(out, s$fail(msg)))
    }
    out
  }

  finish <- function(aborted = FALSE) {
    if (s$terminated) return(list())
    if (aborted) return(s$fail("Request was aborted", aborted = TRUE))
    if (!saw_terminal) return(s$fail("OpenAI Responses stream ended before a terminal response event"))
    if (s$msg$stop_reason == "toolUse" && length(s$pj) > 0L) {
      i <- as.integer(names(s$pj)[[1]])
      return(s$fail(sprintf("OpenAI Responses stream completed with an unfinished tool call: %s (%s)", s$msg$content[[i]]$name, s$msg$content[[i]]$id)))
    }
    if (s$msg$stop_reason == "pending") return(s$fail("OpenAI Responses stream ended without a stop reason"))
    if (s$msg$stop_reason %in% c("error", "aborted")) return(s$fail(s$msg$error_message %||% "An unknown error occurred"))
    s$done()
  }
  # terminal: TRUE once response.completed was seen; callers may close the socket.
  list(push = push, finish = finish, fail = s$fail, message = s$message, terminal = function() saw_terminal)
}

# ---------------------------------------------------------------------------
# Google Gemini (POST {base}/models/{id}:streamGenerateContent?alt=sse)
# ---------------------------------------------------------------------------
normalizer_google <- function(model) {
  s <- .normalizer_core(model)
  cur <- NULL                      # content_index of the open text/thinking block
  counter <- 0L

  close_cur <- function() {
    if (is.null(cur)) return(list())
    b <- s$msg$content[[cur]]
    ev <- if (b$type == "text") s$ev("text_end", content_index = cur, content = b$text)
          else s$ev("thinking_end", content_index = cur, content = b$thinking)
    cur <<- NULL
    list(ev)
  }
  map_stop <- function(r) switch(r, STOP = "stop", MAX_TOKENS = "length", "error")

  push <- function(sse) {
    if (s$terminated) return(list())
    if (!nzchar(sse$data)) return(list())
    ch <- tryCatch(parse_json_with_repair(sse$data), error = function(err) NULL)
    if (is.null(ch)) return(s$fail(paste0("Invalid Gemini chunk: ", sse$data)))
    if (!is.null(ch$error)) return(s$fail(sprintf("%s: %s", ch$error$code %||% "error", ch$error$message %||% "")))
    out <- s$start()
    if (is.null(s$msg$response_id) && !is.null(ch$responseId)) s$msg$response_id <- ch$responseId
    cand <- if (length(ch$candidates)) ch$candidates[[1]] else NULL
    for (part in cand$content$parts %||% list()) {
      if (!is.null(part$text)) {
        thinking <- isTRUE(part$thought)
        want <- if (thinking) "thinking" else "text"
        if (is.null(cur) || s$msg$content[[cur]]$type != want) {
          out <- c(out, close_cur())
          cur <<- s$add_block(if (thinking) list(type = "thinking", thinking = "") else list(type = "text", text = ""))
          out <- c(out, list(s$ev(paste0(want, "_start"), content_index = cur)))
        }
        if (thinking) {
          s$msg$content[[cur]]$thinking <- paste0(s$msg$content[[cur]]$thinking, part$text)
          if (is.character(part$thoughtSignature) && nzchar(part$thoughtSignature)) s$msg$content[[cur]]$thinking_signature <- part$thoughtSignature
          out <- c(out, list(s$ev("thinking_delta", content_index = cur, delta = part$text)))
        } else {
          s$msg$content[[cur]]$text <- paste0(s$msg$content[[cur]]$text, part$text)
          if (is.character(part$thoughtSignature) && nzchar(part$thoughtSignature)) s$msg$content[[cur]]$text_signature <- part$thoughtSignature
          out <- c(out, list(s$ev("text_delta", content_index = cur, delta = part$text)))
        }
      }
      if (!is.null(part$functionCall)) {
        out <- c(out, close_cur())
        fc <- part$functionCall
        ids <- vapply(Filter(function(b) b$type == "tool_call", s$msg$content), function(b) b$id, "")
        id <- fc$id
        if (is.null(id) || !nzchar(id) || id %in% ids) {
          counter <<- counter + 1L
          id <- sprintf("%s_%.0f_%d", fc$name, as.numeric(Sys.time()) * 1000, counter)
        }
        args <- fc$args %||% structure(list(), names = character(0))
        if (length(args) == 0L) args <- structure(list(), names = character(0))
        tc <- list(type = "tool_call", id = id, name = fc$name %||% "", arguments = args)
        if (!is.null(part$thoughtSignature)) tc$thought_signature <- part$thoughtSignature
        i <- s$add_block(tc)
        out <- c(out, list(s$ev("toolcall_start", content_index = i),
          s$ev("toolcall_delta", content_index = i, delta = as.character(jsonlite::toJSON(args, auto_unbox = TRUE, null = "null", digits = NA))),
          s$ev("toolcall_end", content_index = i, tool_call = tc)))
      }
    }
    if (!is.null(cand$finishReason)) {
      s$msg$raw_stop_reason <- cand$finishReason
      s$msg$stop_reason <- map_stop(cand$finishReason)
      has_tool <- any(vapply(s$msg$content, function(b) b$type == "tool_call", logical(1)))
      if (has_tool && s$msg$stop_reason == "stop") s$msg$stop_reason <- "toolUse"
    }
    u <- ch$usageMetadata
    if (!is.null(u)) {
      cached <- u$cachedContentTokenCount %||% 0
      s$msg$usage <- calculate_cost(model, list(
        input = (u$promptTokenCount %||% 0) - cached,
        output = (u$candidatesTokenCount %||% 0) + (u$thoughtsTokenCount %||% 0),
        cache_read = cached, cache_write = 0, reasoning = u$thoughtsTokenCount %||% 0,
        total_tokens = u$totalTokenCount %||% 0, cost = usage_zero()$cost))
    }
    out
  }

  finish <- function(aborted = FALSE) {
    if (s$terminated) return(list())
    out <- close_cur()
    if (aborted) return(c(out, s$fail("Request was aborted", aborted = TRUE)))
    if (s$msg$stop_reason == "pending") return(c(out, s$fail("Google stream ended without a finish reason")))
    if (s$msg$stop_reason %in% c("error", "aborted")) {
      return(c(out, s$fail(if (!is.null(s$msg$raw_stop_reason)) paste0("Provider stopped with: ", s$msg$raw_stop_reason) else "An unknown error occurred")))
    }
    c(out, s$done())
  }
  list(push = push, finish = finish, fail = s$fail, message = s$message)
}

normalizer_for <- function(model) {
  switch(model$api,
    "anthropic-messages" = normalizer_anthropic(model),
    "openai-completions" = normalizer_openai_completions(model),
    "openai-responses" = , "openai-codex-responses" = , "azure-openai-responses" = normalizer_openai_responses(model),
    "google-generative-ai" = normalizer_google(model),
    stop("No normaliser for api: ", model$api))
}

# Drive a normaliser from raw bytes (fixture replay or live connection chunks).
normalize_stream <- function(model, chunks, on_event = NULL) {
  norm <- normalizer_for(model)
  sse <- sse_parser()
  events <- list()
  emit <- function(evs) for (e in evs) {
    events[[length(events) + 1L]] <<- e
    if (!is.null(on_event)) on_event(e, norm)
  }
  for (ch in chunks) for (s in sse$feed(ch)) emit(norm$push(s))
  for (s in sse$flush()) emit(norm$push(s))
  emit(norm$finish())
  list(events = events, message = norm$message())
}
```

Test script `test_normalize.R` (replays the fixtures of section 3.7 in
37-byte network chunks and checks that chunk sizes 1, 5, 64 and 4096 give
identical events). The fixture files of section 3.7 end with one blank line
after the last event. The script also needs two small fixtures that section 3.7
does not show (added by the verifier, copied byte for byte from the prototype
directory so the script can be reproduced from this report alone):

`fixtures/anthropic_error.sse`:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_01abc","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":25,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Partial ans"}}

event: error
data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}

```

`fixtures/anthropic_truncated.sse` (the stream stops mid tool call, without
`content_block_stop` or `message_stop`):

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_01trunc","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":25,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01cut","name":"write","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"path\": \"a.R\", \"content\": \"x <- "}}

```

The script:

```r
suppressPackageStartupMessages(library(jsonlite))
source("R/sse.R"); source("R/partial_json.R"); source("R/normalize.R")

js <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
read_raw <- function(path) readBin(path, "raw", n = file.info(path)$size)
chunk <- function(bytes, size) {
  idx <- seq(1L, length(bytes), by = size)
  lapply(idx, function(i) bytes[i:min(length(bytes), i + size - 1L)])
}
fmt_event <- function(e) {
  extra <- switch(e$type,
    text_delta = , thinking_delta = , toolcall_delta = sprintf("[%d] %s", e$content_index, encodeString(e$delta, quote = '"')),
    text_start = , thinking_start = , toolcall_start = sprintf("[%d]", e$content_index),
    text_end = , thinking_end = sprintf("[%d] %d chars", e$content_index, nchar(e$content)),
    toolcall_end = sprintf("[%d] %s(%s) id=%s", e$content_index, e$tool_call$name, js(e$tool_call$arguments), e$tool_call$id),
    done = sprintf("reason=%s", e$reason),
    error = sprintf("reason=%s msg=%s", e$reason, e$error$error_message),
    "")
  sprintf("  %-15s %s", e$type, extra)
}

models <- list(
  anthropic = list(id = "claude-opus-5-5", api = "anthropic-messages", provider = "anthropic",
    cost = list(input = 4, output = 20, cache_read = 0.2, cache_write = 5)),
  openai_cc = list(id = "gpt-5.5", api = "openai-completions", provider = "openai",
    cost = list(input = 1.25, output = 10, cache_read = 0.125, cache_write = 0)),
  openai_resp = list(id = "gpt-5.5", api = "openai-responses", provider = "openai",
    cost = list(input = 1.25, output = 10, cache_read = 0.125, cache_write = 0,
      tiers = list(list(input_tokens_above = 272000, input = 2.5, output = 15, cache_read = 0.25, cache_write = 0)))),
  google = list(id = "gemini-3.5-flash", api = "google-generative-ai", provider = "google",
    cost = list(input = 0.3, output = 2.5, cache_read = 0.03, cache_write = 0))
)

run <- function(title, model, file, chunk_size = 37L, show_partial_args = FALSE) {
  cat("\n==================================================================\n")
  cat(title, " (", file, ", network chunk size ", chunk_size, " bytes)\n", sep = "")
  bytes <- read_raw(file.path("fixtures", file))
  partial_log <- character()
  res <- normalize_stream(model, chunk(bytes, chunk_size), on_event = function(e, norm) {
    if (show_partial_args && e$type == "toolcall_delta") {
      partial_log[[length(partial_log) + 1L]] <<- js(norm$message()$content[[e$content_index]]$arguments)
    }
  })
  cat(vapply(res$events, fmt_event, ""), sep = "\n")
  if (length(partial_log)) {
    cat("  -- partial tool arguments visible after each toolcall_delta:\n")
    cat(paste0("     ", partial_log), sep = "\n")
  }
  m <- res$message
  cat("  -- final message: stop_reason=", m$stop_reason, " raw=", m$raw_stop_reason %||% "NA",
      " response_id=", m$response_id %||% "NA", "\n", sep = "")
  cat("     blocks: ", paste(vapply(m$content, function(b) b$type, ""), collapse = ", "), "\n", sep = "")
  cat("     usage: ", js(m$usage[setdiff(names(m$usage), "cost")]), "\n", sep = "")
  cat("     cost : ", js(lapply(m$usage$cost, function(x) round(x, 6))), "\n", sep = "")
  # invariance to network chunking
  ref <- normalize_stream(model, list(bytes))
  strip <- function(r) lapply(r$events, function(e) { e$message$timestamp <- NULL; e$error$timestamp <- NULL; if (!is.null(e$tool_call)) e$tool_call$id <- sub("_[0-9]+_", "_T_", e$tool_call$id); e })
  same <- vapply(c(1L, 5L, 64L, 4096L), function(cs) identical(strip(normalize_stream(model, chunk(bytes, cs))), strip(ref)), NA)
  cat("     identical events for chunk sizes 1/5/64/4096: ", paste(same, collapse = " "), "\n", sep = "")
  invisible(res)
}

a <- run("Anthropic Messages: thinking + text + tool_use", models$anthropic, "anthropic_tool.sse", show_partial_args = TRUE)
cat("     text block: ", a$message$content[[2]]$text, "\n", sep = "")
cat("     thinking signature: ", a$message$content[[1]]$thinking_signature, "\n", sep = "")
stopifnot(identical(a$message$content[[3]]$arguments$code, "aggregate(mpg ~ cyl, data = mtcars, FUN = mean)\nprint(\"done\")"))
stopifnot(isTRUE(a$message$content[[3]]$arguments$capture_plots), a$message$content[[3]]$arguments$timeout_s == 30)
# expected cost: input 2140*4 + output 187*20 + cache_read 18000*0.2 + cache_write 1200*5, per 1e6
stopifnot(isTRUE(all.equal(a$message$usage$cost$total, (2140 * 4 + 187 * 20 + 18000 * 0.2 + 1200 * 5) / 1e6)))

run("Anthropic Messages: mid-stream error event", models$anthropic, "anthropic_error.sse")
t <- run("Anthropic Messages: connection dropped mid tool call", models$anthropic, "anthropic_truncated.sse")
cat("     partial content kept on error: ", js(t$message$content[[1]]$arguments), "\n", sep = "")

o <- run("OpenAI Chat Completions: reasoning + text + 2 parallel tool calls", models$openai_cc, "openai_completions_tools.sse", show_partial_args = TRUE)
stopifnot(identical(o$message$content[[4]]$arguments$paths, list("R", "tests")))
stopifnot(o$message$usage$input == 1500 - 1024, o$message$usage$cache_read == 1024)

r <- run("OpenAI Responses: reasoning + message + function_call", models$openai_resp, "openai_responses_tool.sse")
cat("     tool call id (call_id|item_id): ", r$message$content[[3]]$id, "\n", sep = "")
cat("     text_signature: ", r$message$content[[2]]$text_signature, "\n", sep = "")
cat("     thinking_signature (reasoning item for replay): ", r$message$content[[1]]$thinking_signature, "\n", sep = "")

g <- run("Google Gemini streamGenerateContent: thought + text + functionCall", models$google, "google_tool.sse")
cat("     thought_signature on tool call: ", g$message$content[[3]]$thought_signature, "\n", sep = "")

cat("\n== tiered pricing check (port of calculateCost) ==\n")
u <- list(input = 300000, output = 1000, cache_read = 0, cache_write = 0)
cat("  >272k input tokens -> tier rates: ", js(calculate_cost(models$openai_resp, u)$cost), "\n")
u1h <- list(input = 100, output = 10, cache_read = 0, cache_write = 1000, cache_write_1h = 400)
cat("  anthropic 1h cache write (600 short @5 + 400 long @2x input 4): ", js(calculate_cost(models$anthropic, u1h)$cost), "\n")
stopifnot(isTRUE(all.equal(calculate_cost(models$anthropic, u1h)$cost$cache_write, (5 * 600 + 4 * 2 * 400) / 1e6)))

cat("\n== throughput: 6000 text deltas through SSE decoder + Anthropic normaliser ==\n")
mk <- function(i) sprintf('event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"token%d "}}\n\n', i)
body <- paste0(
  'event: message_start\ndata: {"type":"message_start","message":{"id":"m","model":"claude-opus-5-5","usage":{"input_tokens":1,"output_tokens":1}}}\n\n',
  'event: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n',
  paste(vapply(1:6000, mk, ""), collapse = ""),
  'event: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\n',
  'event: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":6000}}\n\n',
  'event: message_stop\ndata: {"type":"message_stop"}\n\n')
bb <- charToRaw(body)
el <- system.time(res <- normalize_stream(models$anthropic, chunk(bb, 1400L)))[["elapsed"]]
cat(sprintf("  %d bytes, %d events in %.2fs (%.0f events/s); final text %d chars\n",
            length(bb), length(res$events), el, length(res$events) / el, nchar(res$message$content[[1]]$text)))
cat("\nALL NORMALISER CHECKS PASSED\n")
```

Observed output:

```

==================================================================
Anthropic Messages: thinking + text + tool_use (anthropic_tool.sse, network chunk size 37 bytes)
  start           
  thinking_start  [1]
  thinking_delta  [1] "The user wants the mean of mpg by cyl. "
  thinking_delta  [1] "mtcars is already loaded, so I can run R directly."
  thinking_end    [1] 89 chars
  text_start      [2]
  text_delta      [2] "I'll compute that in your session"
  text_delta      [2] " <U+2014> caf<U+00E9> <U+0001F600>."
  text_end        [2] 43 chars
  toolcall_start  [3]
  toolcall_delta  [3] ""
  toolcall_delta  [3] "{\"code\": \"aggregate(mpg ~ cyl"
  toolcall_delta  [3] ", data = mtcars, FUN = mean)\\nprint(\\\"done\\\")\", \"capt"
  toolcall_delta  [3] "ure_plots\": tru"
  toolcall_delta  [3] "e, \"timeout_s\": 30}"
  toolcall_end    [3] r_eval({"code":"aggregate(mpg ~ cyl, data = mtcars, FUN = mean)\nprint(\"done\")","capture_plots":true,"timeout_s":30}) id=toolu_01T1x1fJ34qAmk2tNTrN7Up6
  done            reason=toolUse
  -- partial tool arguments visible after each toolcall_delta:
     {}
     {"code":"aggregate(mpg ~ cyl"}
     {"code":"aggregate(mpg ~ cyl, data = mtcars, FUN = mean)\nprint(\"done\")"}
     {"code":"aggregate(mpg ~ cyl, data = mtcars, FUN = mean)\nprint(\"done\")","capture_plots":true}
     {"code":"aggregate(mpg ~ cyl, data = mtcars, FUN = mean)\nprint(\"done\")","capture_plots":true,"timeout_s":30}
  -- final message: stop_reason=toolUse raw=tool_use response_id=msg_01XFDUDYJgAACzvnptvVoYEL
     blocks: thinking, text, tool_call
     usage: {"input":2140,"output":187,"cache_read":18000,"cache_write":1200,"total_tokens":21527,"cache_write_1h":0,"reasoning":61}
     cost : {"input":0.00856,"output":0.00374,"cache_read":0.0036,"cache_write":0.006,"total":0.0219}
     identical events for chunk sizes 1/5/64/4096: TRUE TRUE TRUE TRUE
     text block: I'll compute that in your session <U+2014> caf<U+00E9> <U+0001F600>.
     thinking signature: EqQBCgIYAhIM1gbcDa9GJwZA2b3hGgxBdjrkzLoky3dl1pkiMOYds

==================================================================
Anthropic Messages: mid-stream error event (anthropic_error.sse, network chunk size 37 bytes)
  start           
  text_start      [1]
  text_delta      [1] "Partial ans"
  error           reason=error msg={"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
  -- final message: stop_reason=error raw=NA response_id=msg_01abc
     blocks: text
     usage: {"input":25,"output":1,"cache_read":0,"cache_write":0,"total_tokens":26,"cache_write_1h":0}
     cost : {"input":0.0001,"output":2e-05,"cache_read":0,"cache_write":0,"total":0.00012}
     identical events for chunk sizes 1/5/64/4096: TRUE TRUE TRUE TRUE

==================================================================
Anthropic Messages: connection dropped mid tool call (anthropic_truncated.sse, network chunk size 37 bytes)
  start           
  toolcall_start  [1]
  toolcall_delta  [1] "{\"path\": \"a.R\", \"content\": \"x <- "
  error           reason=error msg=Anthropic stream ended before message_stop
  -- final message: stop_reason=error raw=NA response_id=msg_01trunc
     blocks: tool_call
     usage: {"input":25,"output":1,"cache_read":0,"cache_write":0,"total_tokens":26,"cache_write_1h":0}
     cost : {"input":0.0001,"output":2e-05,"cache_read":0,"cache_write":0,"total":0.00012}
     identical events for chunk sizes 1/5/64/4096: TRUE TRUE TRUE TRUE
     partial content kept on error: {"path":"a.R","content":"x <- "}

==================================================================
OpenAI Chat Completions: reasoning + text + 2 parallel tool calls (openai_completions_tools.sse, network chunk size 37 bytes)
  start           
  thinking_start  [1]
  thinking_delta  [1] "Need two lookups. "
  text_start      [2]
  text_delta      [2] "Checking both files"
  text_delta      [2] "."
  toolcall_start  [3]
  toolcall_delta  [3] ""
  toolcall_delta  [3] "{\"pa"
  toolcall_delta  [3] "th\":\"R/a.R\"}"
  toolcall_start  [4]
  toolcall_delta  [4] "{\"pattern\":"
  toolcall_delta  [4] "\"TODO\",\"paths\":[\"R\",\"tests\"],\"ignore_case\":false}"
  thinking_end    [1] 18 chars
  text_end        [2] 20 chars
  toolcall_end    [3] read({"path":"R/a.R"}) id=call_Ab12Cd34Ef56Gh78Ij90KlMn
  toolcall_end    [4] grep({"pattern":"TODO","paths":["R","tests"],"ignore_case":false}) id=call_Zy98Xw76Vu54Ts32Rq10PoNm
  done            reason=toolUse
  -- partial tool arguments visible after each toolcall_delta:
     {}
     {}
     {"path":"R/a.R"}
     {}
     {"pattern":"TODO","paths":["R","tests"],"ignore_case":false}
  -- final message: stop_reason=toolUse raw=tool_calls response_id=chatcmpl-B9MHDbslfkBeAs8l4bebGdFOJ6PeG
     blocks: thinking, text, tool_call, tool_call
     usage: {"input":476,"output":96,"cache_read":1024,"cache_write":0,"reasoning":32,"total_tokens":1596}
     cost : {"input":0.000595,"output":0.00096,"cache_read":0.000128,"cache_write":0,"total":0.001683}
     identical events for chunk sizes 1/5/64/4096: TRUE TRUE TRUE TRUE

==================================================================
OpenAI Responses: reasoning + message + function_call (openai_responses_tool.sse, network chunk size 37 bytes)
  start           
  thinking_start  [1]
  thinking_delta  [1] "**Planning the edit**"
  thinking_delta  [1] "\n\n"
  thinking_end    [1] 21 chars
  text_start      [2]
  text_delta      [2] "Editing "
  text_delta      [2] "the file now."
  text_end        [2] 21 chars
  toolcall_start  [3]
  toolcall_delta  [3] "{\"path\":\"R/a.R\",\"old\":\"x <- 1\","
  toolcall_delta  [3] "\"new\":\"x <- 2\"}"
  toolcall_end    [3] edit({"path":"R/a.R","old":"x <- 1","new":"x <- 2"}) id=call_9Zx8Yw7Vu6|fc_0a1b2c
  done            reason=toolUse
  -- final message: stop_reason=toolUse raw=completed response_id=resp_0a1b2c3d4e5f
     blocks: thinking, text, tool_call
     usage: {"input":1104,"output":140,"cache_read":4096,"cache_write":0,"reasoning":64,"total_tokens":5340}
     cost : {"input":0.00138,"output":0.0014,"cache_read":0.000512,"cache_write":0,"total":0.003292}
     identical events for chunk sizes 1/5/64/4096: TRUE TRUE TRUE TRUE
     tool call id (call_id|item_id): call_9Zx8Yw7Vu6|fc_0a1b2c
     text_signature: {"v":1,"id":"msg_0a1b2c","phase":"commentary"}
     thinking_signature (reasoning item for replay): {"id":"rs_0a1b2c","type":"reasoning","encrypted_content":"gAAAAABo2encryptedblob==","summary":[{"type":"summary_text","text":"**Planning the edit**"}]}

==================================================================
Google Gemini streamGenerateContent: thought + text + functionCall (google_tool.sse, network chunk size 37 bytes)
  start           
  thinking_start  [1]
  thinking_delta  [1] "**Working out the query**\nI should list files first."
  thinking_end    [1] 52 chars
  text_start      [2]
  text_delta      [2] "Let me look at "
  text_delta      [2] "the directory."
  text_end        [2] 29 chars
  toolcall_start  [3]
  toolcall_delta  [3] "{\"pattern\":\"*.R\",\"sort\":\"mtime\",\"limit\":20}"
  toolcall_end    [3] find({"pattern":"*.R","sort":"mtime","limit":20}) id=fc_7h2k
  done            reason=toolUse
  -- final message: stop_reason=toolUse raw=STOP response_id=k9_XaJ3vGsmWz7IP
     blocks: thinking, text, tool_call
     usage: {"input":300,"output":74,"cache_read":512,"cache_write":0,"reasoning":43,"total_tokens":886}
     cost : {"input":9e-05,"output":0.000185,"cache_read":1.5e-05,"cache_write":0,"total":0.00029}
     identical events for chunk sizes 1/5/64/4096: TRUE TRUE TRUE TRUE
     thought_signature on tool call: CiQBjz1rX3sigAAAAbase64==

== tiered pricing check (port of calculateCost) ==
  >272k input tokens -> tier rates:  {"input":0.75,"output":0.015,"cache_read":0,"cache_write":0,"total":0.765} 
  anthropic 1h cache write (600 short @5 + 400 long @2x input 4):  {"input":0.0004,"output":0.0002,"cache_read":0,"cache_write":0.0062,"total":0.0068} 

== throughput: 6000 text deltas through SSE decoder + Anthropic normaliser ==
  749398 bytes, 6004 events in 0.69s (8676 events/s); final text 58893 chars

ALL NORMALISER CHECKS PASSED
```

### 5.4 Streaming over real HTTP connections

`test_http_stream.R` - httpuv server in a background process, client with
`httr2::req_perform_connection()` reading 64 bytes at a time, HTTP error
mapping, comparison with `httr2::resp_stream_sse()`:

```r
# End-to-end check over a real local HTTP connection:
#   background R process: httpuv server that streams the Anthropic fixture as
#   text/event-stream in small delayed chunks (chunked transfer encoding);
#   this process: httr2::req_perform_connection() + our own SSE decoder + normaliser.
suppressPackageStartupMessages({ library(httr2); library(jsonlite) })
source("R/sse.R"); source("R/partial_json.R"); source("R/normalize.R")

fixture <- normalizePath("fixtures/anthropic_tool.sse")
port <- httpuv::randomPort()

server <- callr::r_bg(function(port, fixture) {
  bytes <- readBin(fixture, "raw", n = file.info(fixture)$size)
  app <- list(call = function(req) {
    body_in <- rawToChar(req$rook.input$read())
    if (identical(req$PATH_INFO, "/v1/messages")) {
      if (!identical(req$HTTP_X_API_KEY, "test-key")) {
        return(list(status = 401L, headers = list("Content-Type" = "application/json"),
          body = '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}'))
      }
      # stream the body in 61-byte pieces through a fifo-less trick: httpuv accepts a
      # file path body only, so emulate chunking with a temp file served as a whole;
      # real chunk boundaries are exercised by the client reading 64 bytes at a time.
      tmp <- tempfile(fileext = ".sse")
      writeBin(bytes, tmp)
      return(list(status = 200L,
        headers = list("Content-Type" = "text/event-stream; charset=utf-8", "Cache-Control" = "no-cache",
                       "request-id" = "req_local_1", "X-Echo-Len" = as.character(nchar(body_in))),
        body = c(file = tmp)))
    }
    if (identical(req$PATH_INFO, "/overloaded")) {
      return(list(status = 529L, headers = list("Content-Type" = "application/json", "retry-after" = "1"),
        body = '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'))
    }
    list(status = 404L, headers = list("Content-Type" = "text/plain"), body = "not found")
  })
  srv <- httpuv::startServer("127.0.0.1", port, app)
  on.exit(httpuv::stopServer(srv))
  t0 <- Sys.time()
  while (difftime(Sys.time(), t0, units = "secs") < 25) httpuv::service(100)
}, args = list(port = port, fixture = fixture))
on.exit(server$kill(), add = TRUE)

# wait for the listener
for (i in 1:50) {
  ok <- tryCatch({ con <- socketConnection("127.0.0.1", port, open = "r+b", timeout = 1); close(con); TRUE },
                 error = function(e) FALSE, warning = function(w) FALSE)
  if (ok) break
  Sys.sleep(0.1)
}
cat("server listening on port", port, ":", ok, "\n")

model <- list(id = "claude-opus-5-5", api = "anthropic-messages", provider = "anthropic",
              base_url = paste0("http://127.0.0.1:", port),
              cost = list(input = 4, output = 20, cache_read = 0.2, cache_write = 5))

body <- list(
  model = model$id, max_tokens = 64000L, stream = TRUE,
  thinking = list(type = "adaptive", display = "summarized"),
  output_config = list(effort = "high"),
  system = list(list(type = "text", text = "You are gptr.", cache_control = list(type = "ephemeral"))),
  tools = list(list(name = "r_eval", description = "Evaluate R code in the live session",
    eager_input_streaming = TRUE,
    input_schema = list(type = "object",
      properties = list(code = list(type = "string"), capture_plots = list(type = "boolean"), timeout_s = list(type = "number")),
      required = list("code")))),
  messages = list(list(role = "user", content = "mean mpg by cyl?"))
)
cat("request body JSON:\n ", substr(as.character(toJSON(body, auto_unbox = TRUE, null = "null", digits = NA)), 1, 400), "...\n")

stream_request <- function(path, api_key) {
  req <- request(model$base_url) |>
    req_url_path_append(path) |>
    req_headers("x-api-key" = api_key, "anthropic-version" = "2023-06-01",
                "accept" = "text/event-stream", .redact = "x-api-key") |>
    req_user_agent("gptr/0.0.0.9000 (prototype)") |>
    req_body_json(body, auto_unbox = TRUE, null = "null", digits = NA) |>
    req_error(is_error = function(resp) FALSE) |>      # we turn HTTP errors into stream errors ourselves
    req_timeout(30)
  norm <- normalizer_for(model)
  sse <- sse_parser()
  events <- list()
  resp <- tryCatch(req_perform_connection(req, blocking = TRUE), error = function(e) e)
  if (inherits(resp, "error")) return(list(events = norm$fail(conditionMessage(resp)), message = norm$message()))
  on.exit(close(resp), add = TRUE)
  if (resp_status(resp) >= 400L) {
    txt <- paste(rawToChar(resp_stream_raw(resp, kb = 64)), collapse = "")
    msg <- sprintf("%d: %s", resp_status(resp), substr(txt, 1, 4000))
    return(list(events = norm$fail(msg), message = norm$message(), status = resp_status(resp),
                retry_after = resp_header(resp, "retry-after")))
  }
  n_chunks <- 0L
  while (!resp_stream_is_complete(resp)) {
    chunk <- resp_stream_raw(resp, kb = 64 / 1024)       # 64 bytes at a time
    if (length(chunk) == 0L) next
    n_chunks <- n_chunks + 1L
    for (s in sse$feed(chunk)) events <- c(events, norm$push(s))
  }
  for (s in sse$flush()) events <- c(events, norm$push(s))
  events <- c(events, norm$finish())
  list(events = events, message = norm$message(), status = resp_status(resp), chunks = n_chunks,
       request_id = resp_header(resp, "request-id"))
}

res <- stream_request("v1/messages", "test-key")
cat(sprintf("\nHTTP %d, request-id=%s, body read in %d chunks, %d normalised events\n",
            res$status, res$request_id, res$chunks, length(res$events)))
cat("event types: ", paste(vapply(res$events, function(e) e$type, ""), collapse = " "), "\n")
tc <- res$message$content[[3]]
cat("tool call: ", tc$name, " ", as.character(toJSON(tc$arguments, auto_unbox = TRUE)), "\n")
cat("stop_reason: ", res$message$stop_reason, "  cost total: ", res$message$usage$cost$total, "\n")

bad <- stream_request("v1/messages", "wrong-key")
cat("\nwrong key -> events: ", paste(vapply(bad$events, function(e) e$type, ""), collapse = " "),
    " | stop_reason=", bad$message$stop_reason, " | ", bad$message$error_message, "\n", sep = "")
ovl <- stream_request("overloaded", "test-key")
cat("529 -> stop_reason=", ovl$message$stop_reason, " retry-after=", ovl$retry_after, " | ", ovl$message$error_message, "\n", sep = "")
dead <- local({ model$base_url <- "http://127.0.0.1:9"; environment(stream_request)$model <- model; stream_request("v1/messages", "k") })
cat("connection refused -> stop_reason=", dead$message$stop_reason, " | ", substr(dead$message$error_message, 1, 120), "\n", sep = "")

# The same stream through httr2's own SSE reader, for comparison.
environment(stream_request)$model$base_url <- paste0("http://127.0.0.1:", port)
req <- request(paste0("http://127.0.0.1:", port, "/v1/messages")) |>
  req_headers("x-api-key" = "test-key") |> req_body_json(body)
resp <- req_perform_connection(req)
n <- 0L; types <- character()
repeat {
  ev <- resp_stream_sse(resp)
  if (is.null(ev)) break
  n <- n + 1L; types <- c(types, ev$type)
}
close(resp)
cat("\nhttr2::resp_stream_sse saw", n, "events; first fields:", paste(names(ev <- list(type = 1, data = 1, id = 1)), collapse = ","), "\n")
print(table(types))
```

Observed output:

```
server listening on port 6789 : TRUE 
request body JSON:
  {"model":"claude-opus-5-5","max_tokens":64000,"stream":true,"thinking":{"type":"adaptive","display":"summarized"},"output_config":{"effort":"high"},"system":[{"type":"text","text":"You are gptr.","cache_control":{"type":"ephemeral"}}],"tools":[{"name":"r_eval","description":"Evaluate R code in the live session","eager_input_streaming":true,"input_schema":{"type":"object","properties":{"code":{"typ ...

HTTP 200, request-id=req_local_1, body read in 46 chunks, 17 normalised events
event types:  start thinking_start thinking_delta thinking_delta thinking_end text_start text_delta text_delta text_end toolcall_start toolcall_delta toolcall_delta toolcall_delta toolcall_delta toolcall_delta toolcall_end done 
tool call:  r_eval   {"code":"aggregate(mpg ~ cyl, data = mtcars, FUN = mean)\nprint(\"done\")","capture_plots":true,"timeout_s":30} 
stop_reason:  toolUse   cost total:  0.0219 

wrong key -> events: error | stop_reason=error | 401: {"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}
529 -> stop_reason=error retry-after=1 | 529: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
connection refused -> stop_reason=error | Failed to perform HTTP request.
Caused by error in `open.connection()`:
! cannot open the connection

httr2::resp_stream_sse saw 20 events; first fields: type,data,id 
types
content_block_delta content_block_start  content_block_stop       message_delta 
                 10                   3                   3                   1 
      message_start        message_stop                ping 
                  1                   1                   1 
```

`test_slow_stream.R` - raw-socket HTTP/1.1 server that sends the fixture with
chunked transfer encoding, 23 bytes every 15 ms; non-blocking polling client;
client-side abort; idle timeout; three concurrent streams through
`curl::multi_run()`:

```r
# True incremental streaming test: a raw-socket HTTP/1.1 server (background R
# process) sends the fixture with Transfer-Encoding: chunked, 23 bytes every
# 15 ms (so chunk borders fall inside JSON strings and multi-byte characters).
suppressPackageStartupMessages({ library(httr2); library(jsonlite); library(curl) })
source("R/sse.R"); source("R/partial_json.R"); source("R/normalize.R")

slow_server <- function(port, fixture, piece = 23L, delay = 0.015, n_conn = 1L, stall_after = Inf,
                        ready_file = NULL) {
  bytes <- readBin(fixture, "raw", n = file.info(fixture)$size)
  srv <- serverSocket(port)
  on.exit(close(srv))
  if (!is.null(ready_file)) file.create(ready_file)        # listening: tell the parent
  for (k in seq_len(n_conn)) {
    con <- socketAccept(srv, blocking = TRUE, open = "r+b", timeout = 20)
    # read request head + body (Content-Length)
    head <- raw(0)
    repeat {
      b <- readBin(con, "raw", 1L)
      if (length(b) == 0L) break
      head <- c(head, b)
      nh <- length(head)
      if (nh >= 4L && identical(head[(nh - 3L):nh], as.raw(c(13, 10, 13, 10)))) break
    }
    htxt <- rawToChar(head)
    cl <- regmatches(htxt, regexpr("(?i)content-length: *[0-9]+", htxt, perl = TRUE))
    if (length(cl)) readBin(con, "raw", as.integer(sub(".*: *", "", cl)))
    writeBin(charToRaw("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"), con)
    flush(con)
    i <- 1L
    sent <- 0L
    ok <- TRUE
    while (i <= length(bytes) && ok) {
      j <- min(length(bytes), i + piece - 1L)
      part <- bytes[i:j]
      ok <- tryCatch({
        writeBin(c(charToRaw(sprintf("%x\r\n", length(part))), part, as.raw(c(13, 10))), con)
        flush(con); TRUE
      }, error = function(e) FALSE, warning = function(w) FALSE)
      sent <- sent + length(part)
      if (sent >= stall_after) { Sys.sleep(6); ok <- FALSE }
      i <- j + 1L
      Sys.sleep(delay)
    }
    if (ok) tryCatch({ writeBin(charToRaw("0\r\n\r\n"), con); flush(con) }, error = function(e) NULL, warning = function(w) NULL)
    close(con)
  }
}
start_server <- function(...) {
  port <- httpuv::randomPort()
  ready <- tempfile("slow-server-ready-")
  p <- callr::r_bg(slow_server, args = list(port = port, ..., ready_file = ready))
  # Wait until the child has created its listening socket. Probing the port would
  # consume the only connection, so the child signals readiness through a file.
  # (Verifier fix: the original fixed 0.4 s wait raced the child's start-up and
  # failed 3 of 6 runs under concurrent load with "cannot open the connection".)
  deadline <- proc.time()[["elapsed"]] + 30
  while (!file.exists(ready)) {
    if (!p$is_alive()) stop("server died: ", p$read_all_error())
    if (proc.time()[["elapsed"]] > deadline) stop("server did not start within 30 s")
    Sys.sleep(0.05)
  }
  unlink(ready)
  list(port = port, proc = p)
}

model <- list(id = "claude-opus-5-5", api = "anthropic-messages", provider = "anthropic",
              cost = list(input = 4, output = 20, cache_read = 0.2, cache_write = 5))
fixture <- normalizePath("fixtures/anthropic_tool.sse")

# --- 1. non-blocking polling loop (keeps the R session interruptible) ---------------
stream_poll <- function(url, stop_after_events = Inf, idle_timeout = 3) {
  req <- request(url) |> req_headers("x-api-key" = "k") |>
    req_body_json(list(stream = TRUE)) |> req_error(is_error = function(r) FALSE)
  norm <- normalizer_for(model); sse <- sse_parser()
  events <- list(); stamps <- numeric()
  t0 <- proc.time()[["elapsed"]]
  resp <- req_perform_connection(req, blocking = FALSE)
  on.exit(close(resp), add = TRUE)
  last_data <- proc.time()[["elapsed"]]
  aborted <- FALSE; stalled <- FALSE
  tryCatch({
    while (!resp_stream_is_complete(resp)) {
      chunk <- resp_stream_raw(resp, kb = 32)
      if (length(chunk) == 0L) {
        if (proc.time()[["elapsed"]] - last_data > idle_timeout) { stalled <- TRUE; break }
        Sys.sleep(0.01)                       # interrupt window
        next
      }
      last_data <- proc.time()[["elapsed"]]
      for (s in sse$feed(chunk)) for (e in norm$push(s)) {
        events[[length(events) + 1L]] <- e
        stamps[[length(stamps) + 1L]] <- proc.time()[["elapsed"]] - t0
      }
      if (length(events) >= stop_after_events) { aborted <- TRUE; break }
    }
  }, interrupt = function(i) aborted <<- TRUE)
  tail_events <- if (stalled) norm$fail(sprintf("Stream stalled: no data for %gs", idle_timeout))
                 else if (aborted) norm$finish(aborted = TRUE)
                 else { for (s in sse$flush()) events <- c(events, norm$push(s)); norm$finish() }
  list(events = c(events, tail_events), stamps = stamps, message = norm$message(),
       elapsed = proc.time()[["elapsed"]] - t0)
}

s1 <- start_server(fixture = fixture)
r1 <- stream_poll(sprintf("http://127.0.0.1:%d/v1/messages", s1$port))
cat(sprintf("1. polling: %d events in %.2fs; first event after %.2fs, last streamed event after %.2fs; stop_reason=%s\n",
            length(r1$events), r1$elapsed, r1$stamps[[1]], r1$stamps[[length(r1$stamps)]], r1$message$stop_reason))
cat("   text: ", r1$message$content[[2]]$text, "\n")
cat("   args: ", as.character(toJSON(r1$message$content[[3]]$arguments, auto_unbox = TRUE)), "\n")
invisible(s1$proc$kill())

# --- 2. client-side abort after 8 events ------------------------------------------
s2 <- start_server(fixture = fixture)
r2 <- stream_poll(sprintf("http://127.0.0.1:%d/v1/messages", s2$port), stop_after_events = 8)
cat(sprintf("2. abort: %d events in %.2fs; last=%s reason=%s; blocks kept: %s\n", length(r2$events), r2$elapsed,
            r2$events[[length(r2$events)]]$type, r2$message$stop_reason,
            paste(vapply(r2$message$content, function(b) b$type, ""), collapse = ",")))
invisible(s2$proc$kill())

# --- 3. server stalls mid-stream -> idle timeout ----------------------------------
s3 <- start_server(fixture = fixture, stall_after = 900)
r3 <- stream_poll(sprintf("http://127.0.0.1:%d/v1/messages", s3$port), idle_timeout = 1.5)
cat(sprintf("3. stall: %d events in %.2fs; reason=%s msg=%s\n", length(r3$events), r3$elapsed,
            r3$message$stop_reason, r3$message$error_message))
invisible(s3$proc$kill())

# --- 4. three concurrent streams in ONE R process via curl multi -------------------
servers <- lapply(1:3, function(i) start_server(fixture = fixture, delay = 0.01 * i))
pool <- curl::new_pool()
states <- lapply(1:3, function(i) list(norm = normalizer_for(model), sse = sse_parser(), n = 0L, done = FALSE, order = integer()))
env <- environment()
tick <- 0L
for (i in 1:3) local({
  ii <- i
  h <- curl::new_handle(url = sprintf("http://127.0.0.1:%d/v1/messages", servers[[ii]]$port))
  curl::handle_setopt(h, post = TRUE, postfields = '{"stream":true}')
  curl::handle_setheaders(h, "content-type" = "application/json", "x-api-key" = "k")
  curl::multi_add(h, pool = pool,
    data = function(chunk, final = FALSE) {
      st <- env$states[[ii]]
      for (s in st$sse$feed(chunk)) for (e in st$norm$push(s)) {
        env$tick <- env$tick + 1L
        env$states[[ii]]$n <- env$states[[ii]]$n + 1L
        env$states[[ii]]$order <- c(env$states[[ii]]$order, env$tick)
      }
    },
    done = function(res) { st <- env$states[[ii]]; ev <- st$norm$finish(); env$states[[ii]]$done <- TRUE; env$states[[ii]]$status <- res$status_code },
    fail = function(msg) { st <- env$states[[ii]]; st$norm$fail(msg); env$states[[ii]]$done <- TRUE })
})
t0 <- proc.time()[["elapsed"]]
repeat {
  out <- curl::multi_run(timeout = 0.05, pool = pool)     # returns regularly -> interruptible, can drive a UI
  if (out$pending == 0L) break
}
el <- proc.time()[["elapsed"]] - t0
for (i in 1:3) cat(sprintf("4. stream %d: status=%s events=%d stop_reason=%s (event ticks %d..%d)\n", i, states[[i]]$status,
  states[[i]]$n, states[[i]]$norm$message()$stop_reason, min(states[[i]]$order), max(states[[i]]$order)))
interleaved <- max(states[[1]]$order) > min(states[[3]]$order)
cat(sprintf("   3 streams finished in %.2fs wall clock; interleaved=%s\n", el, interleaved))
invisible(lapply(servers, function(s) s$proc$kill()))
```

Observed output:

```
1. polling: 17 events in 2.26s; first event after 0.33s, last streamed event after 2.04s; stop_reason=toolUse
   text:  I'll compute that in your session <U+2014> caf<U+00E9> <U+0001F600>. 
   args:  {"code":"aggregate(mpg ~ cyl, data = mtcars, FUN = mean)\nprint(\"done\")","capture_plots":true,"timeout_s":30} 
2. abort: 9 events in 1.28s; last=error reason=aborted; blocks kept: thinking,text
3. stall: 4 events in 2.22s; reason=error msg=Stream stalled: no data for 1.5s
4. stream 1: status=200 events=16 stop_reason=toolUse (event ticks 1..26)
4. stream 2: status=200 events=16 stop_reason=toolUse (event ticks 4..42)
4. stream 3: status=200 events=16 stop_reason=toolUse (event ticks 7..48)
   3 streams finished in 4.15s wall clock; interleaved=TRUE
```

Reading: the first normalised event arrived 0.33 s after the request started
and the last 2.04 s after, so events are delivered while the response is still
being received. Aborting keeps the blocks received so far and yields
`stop_reason = "aborted"`. Three streams interleave in one R process.

### 5.5 Messages, hand-off and request builders - `R/messages.R`

```r
# Unified messages -> provider request bodies (ports of Pi's transformMessages,
# convertMessages and buildParams for the four main wire formats).

`%||%` <- function(a, b) if (is.null(a)) b else a
empty_obj <- function() structure(list(), names = character(0))
now_ms <- function() round(as.numeric(Sys.time()) * 1000)
as_obj <- function(x) if (length(x) == 0L) empty_obj() else x

user_message <- function(content) list(role = "user", content = content, timestamp = now_ms())
text_block <- function(text) list(type = "text", text = text)
image_block <- function(data, mime_type) list(type = "image", data = data, mime_type = mime_type)
tool_result_message <- function(tool_call_id, tool_name, content, is_error = FALSE) {
  if (is.character(content)) content <- list(text_block(content))
  list(role = "tool_result", tool_call_id = tool_call_id, tool_name = tool_name, content = content,
       is_error = is_error, timestamp = now_ms())
}

short_hash <- function(x) substr(as.character(openssl::sha256(charToRaw(enc2utf8(x)))), 1L, 12L)
sanitize_id <- function(id, max = 64L) substr(gsub("[^a-zA-Z0-9_-]", "_", id), 1L, max)

# ---- cross-provider hand-off ---------------------------------------------------
transform_messages <- function(messages, model, normalize_id = NULL) {
  id_map <- list()
  supports_images <- "image" %in% (model$input %||% "text")
  strip_images <- function(content, placeholder) {
    out <- list(); prev <- FALSE
    for (b in content) {
      if (identical(b$type, "image")) { if (!prev) out[[length(out) + 1L]] <- text_block(placeholder); prev <- TRUE; next }
      out[[length(out) + 1L]] <- b
      prev <- identical(b$text, placeholder)
    }
    out
  }
  pass1 <- lapply(messages, function(msg) {
    if (is.null(msg$content)) msg$content <- list()
    if (!supports_images) {
      if (msg$role == "user" && is.list(msg$content)) msg$content <- strip_images(msg$content, "(image omitted: model does not support images)")
      if (msg$role == "tool_result") msg$content <- strip_images(msg$content, "(tool image omitted: model does not support images)")
    }
    msg
  })
  out1 <- vector("list", length(pass1))
  for (k in seq_along(pass1)) {
    msg <- pass1[[k]]
    if (msg$role == "tool_result") {
      mapped <- id_map[[msg$tool_call_id]]
      if (!is.null(mapped)) msg$tool_call_id <- mapped
    } else if (msg$role == "assistant") {
      same <- identical(msg$provider, model$provider) && identical(msg$api, model$api) && identical(msg$model, model$id)
      blocks <- list()
      for (b in msg$content) {
        if (b$type == "thinking") {
          if (isTRUE(b$redacted)) { if (same) blocks[[length(blocks) + 1L]] <- b; next }
          if (same && nzchar(b$thinking_signature %||% "")) { blocks[[length(blocks) + 1L]] <- b; next }
          if (!nzchar(trimws(b$thinking %||% ""))) next
          blocks[[length(blocks) + 1L]] <- if (same) b else text_block(b$thinking)
        } else if (b$type == "text") {
          blocks[[length(blocks) + 1L]] <- if (same) b else text_block(b$text)
        } else if (b$type == "tool_call") {
          if (!same) {
            b$thought_signature <- NULL
            if (!is.null(normalize_id)) {
              nid <- normalize_id(b$id, model, msg)
              if (!identical(nid, b$id)) { id_map[[b$id]] <- nid; b$id <- nid }
            }
          }
          blocks[[length(blocks) + 1L]] <- b
        } else blocks[[length(blocks) + 1L]] <- b
      }
      msg$content <- blocks
    }
    out1[[k]] <- msg
  }
  # second pass: drop failed turns, synthesise results for orphaned tool calls
  res <- list(); pending <- list(); seen <- character()
  close_pending <- function() {
    for (tc in pending) if (!(tc$id %in% seen)) {
      res[[length(res) + 1L]] <<- tool_result_message(tc$id, tc$name, "No result provided", is_error = TRUE)
    }
    pending <<- list(); seen <<- character()
  }
  for (msg in out1) {
    if (msg$role == "assistant") {
      close_pending()
      if (msg$stop_reason %in% c("error", "aborted")) next
      calls <- Filter(function(b) b$type == "tool_call", msg$content)
      if (length(calls)) { pending <- calls; seen <- character() }
      res[[length(res) + 1L]] <- msg
    } else if (msg$role == "tool_result") {
      seen <- c(seen, msg$tool_call_id)
      res[[length(res) + 1L]] <- msg
    } else {
      close_pending()
      res[[length(res) + 1L]] <- msg
    }
  }
  close_pending()
  res
}

# ---- thinking level helpers ------------------------------------------------------
THINKING_LEVELS <- c("off", "minimal", "low", "medium", "high", "xhigh", "max")
supported_thinking_levels <- function(model) {
  if (!isTRUE(model$reasoning)) return("off")
  map <- model$thinking_level_map %||% list()
  Filter(function(l) {
    if (l %in% names(map) && is.null(map[[l]])) return(FALSE)          # explicit NULL = unsupported
    if (l %in% c("xhigh", "max")) return(l %in% names(map))            # opt-in levels
    TRUE
  }, THINKING_LEVELS)
}
clamp_thinking_level <- function(model, level) {
  av <- supported_thinking_levels(model)
  if (level %in% av) return(level)
  i <- match(level, THINKING_LEVELS)
  if (is.na(i)) return(av[[1]] %||% "off")
  for (l in THINKING_LEVELS[i:length(THINKING_LEVELS)]) if (l %in% av) return(l)
  for (l in rev(THINKING_LEVELS[seq_len(i - 1L)])) if (l %in% av) return(l)
  av[[1]] %||% "off"
}
DEFAULT_THINKING_BUDGETS <- c(minimal = 1024, low = 2048, medium = 8192, high = 16384)
thinking_budget <- function(level, custom = NULL) {
  b <- DEFAULT_THINKING_BUDGETS; if (!is.null(custom)) b[names(custom)] <- unlist(custom)
  if (level %in% c("xhigh", "max")) level <- "high"
  b[[level]]
}

# ---- Anthropic Messages ----------------------------------------------------------
anthropic_content <- function(content) {
  has_img <- any(vapply(content, function(b) identical(b$type, "image"), NA))
  if (!has_img) return(paste(vapply(content, function(b) b$text, ""), collapse = "\n"))
  blocks <- lapply(content, function(b) if (b$type == "text") list(type = "text", text = b$text) else
    list(type = "image", source = list(type = "base64", media_type = b$mime_type, data = b$data)))
  if (!any(vapply(blocks, function(b) b$type == "text", NA))) blocks <- c(list(list(type = "text", text = "(see attached image)")), blocks)
  blocks
}
build_anthropic <- function(model, context, api_key, reasoning = NULL, max_tokens = NULL,
                            cache_retention = "short", temperature = NULL, tool_choice = NULL) {
  cache <- if (cache_retention == "none") NULL else c(list(type = "ephemeral"), if (cache_retention == "long") list(ttl = "1h"))
  msgs <- transform_messages(context$messages, model, function(id, ...) sanitize_id(id, 64L))
  out <- list(); i <- 1L
  while (i <= length(msgs)) {
    m <- msgs[[i]]
    if (m$role == "user") {
      if (is.character(m$content)) { if (nzchar(trimws(m$content))) out[[length(out) + 1L]] <- list(role = "user", content = m$content) }
      else {
        blocks <- Filter(function(b) b$type != "text" || nzchar(trimws(b$text)), m$content)
        blocks <- lapply(blocks, function(b) if (b$type == "text") list(type = "text", text = b$text) else
          list(type = "image", source = list(type = "base64", media_type = b$mime_type, data = b$data)))
        if (length(blocks)) out[[length(out) + 1L]] <- list(role = "user", content = blocks)
      }
    } else if (m$role == "assistant") {
      blocks <- list()
      for (b in m$content) {
        if (b$type == "text") { if (nzchar(trimws(b$text))) blocks[[length(blocks) + 1L]] <- list(type = "text", text = b$text) }
        else if (b$type == "thinking") {
          if (isTRUE(b$redacted)) { blocks[[length(blocks) + 1L]] <- list(type = "redacted_thinking", data = b$thinking_signature); next }
          has_sig <- nzchar(trimws(b$thinking_signature %||% ""))
          if (!nzchar(trimws(b$thinking)) && !has_sig) next
          blocks[[length(blocks) + 1L]] <- if (has_sig) list(type = "thinking", thinking = b$thinking, signature = b$thinking_signature)
                                           else list(type = "text", text = b$thinking)     # unsigned (aborted) thinking -> text
        } else if (b$type == "tool_call") {
          blocks[[length(blocks) + 1L]] <- list(type = "tool_use", id = b$id, name = b$name, input = as_obj(b$arguments))
        }
      }
      if (length(blocks)) out[[length(out) + 1L]] <- list(role = "assistant", content = blocks)
    } else if (m$role == "tool_result") {
      results <- list()
      while (i <= length(msgs) && msgs[[i]]$role == "tool_result") {     # all consecutive results -> ONE user message
        r <- msgs[[i]]
        results[[length(results) + 1L]] <- list(type = "tool_result", tool_use_id = r$tool_call_id,
          content = anthropic_content(r$content), is_error = isTRUE(r$is_error))
        i <- i + 1L
      }
      out[[length(out) + 1L]] <- list(role = "user", content = results)
      next
    }
    i <- i + 1L
  }
  if (!is.null(cache) && length(out)) {
    last <- out[[length(out)]]
    if (last$role == "user") {
      if (is.character(last$content)) last$content <- list(list(type = "text", text = last$content, cache_control = cache))
      else last$content[[length(last$content)]]$cache_control <- cache
      out[[length(out)]] <- last
    }
  }
  body <- list(model = model$id, messages = out, max_tokens = max_tokens %||% model$max_tokens, stream = TRUE)
  if (nzchar(context$system_prompt %||% "")) body$system <- list(c(list(type = "text", text = context$system_prompt), if (!is.null(cache)) list(cache_control = cache)))
  tools <- context$tools %||% list()
  if (length(tools)) {
    body$tools <- lapply(seq_along(tools), function(k) {
      t <- tools[[k]]
      c(list(name = t$name, description = t$description, eager_input_streaming = TRUE,
             input_schema = list(type = "object", properties = as_obj(t$parameters$properties), required = as.list(t$parameters$required %||% list()))),
        if (!is.null(cache) && k == length(tools)) list(cache_control = cache))
    })
  }
  adaptive <- isTRUE(model$compat$force_adaptive_thinking)
  if (isTRUE(model$reasoning)) {
    if (!is.null(reasoning) && reasoning != "off") {
      if (adaptive) {
        body$thinking <- list(type = "adaptive", display = "summarized")
        effort <- model$thinking_level_map[[reasoning]] %||% switch(reasoning, minimal = , low = "low", medium = "medium", "high")
        body$output_config <- list(effort = effort)
      } else {
        budget <- thinking_budget(reasoning)
        body$max_tokens <- min((max_tokens %||% 0) + budget, model$max_tokens)
        if (is.null(max_tokens)) body$max_tokens <- model$max_tokens
        body$thinking <- list(type = "enabled", budget_tokens = min(budget, max(0, body$max_tokens - 1024)), display = "summarized")
      }
    } else if (!("off" %in% names(model$thinking_level_map) && is.null(model$thinking_level_map$off))) {
      body$thinking <- list(type = "disabled")
    }
  }
  if (!is.null(temperature) && is.null(body$thinking$budget_tokens) && !adaptive && !isFALSE(model$compat$supports_temperature)) body$temperature <- temperature
  if (!is.null(tool_choice)) body$tool_choice <- if (is.character(tool_choice)) list(type = tool_choice) else tool_choice
  betas <- character()
  if (isTRUE(model$reasoning) && identical(body$thinking$type, "enabled")) betas <- c(betas, "interleaved-thinking-2025-05-14")
  headers <- c(list("x-api-key" = api_key, "anthropic-version" = "2023-06-01", "content-type" = "application/json", accept = "text/event-stream"),
               if (length(betas)) list("anthropic-beta" = paste(betas, collapse = ",")))
  list(url = paste0(sub("/+$", "", model$base_url), "/v1/messages"), headers = headers, body = body)
}

# ---- OpenAI Chat Completions -------------------------------------------------------
openai_cc_id <- function(id, model) {
  if (grepl("|", id, fixed = TRUE)) {
    p <- regmatches(id, regexpr("|", id, fixed = TRUE), invert = TRUE)[[1]]
    call <- gsub("[^a-zA-Z0-9_-]", "_", p[[1]]); item <- gsub("[^a-zA-Z0-9_-]", "_", p[[2]])
    combined <- if (nzchar(item)) paste0(call, "_", item) else call
    if (nchar(combined) <= 40L) return(combined)
    h <- substr(short_hash(id), 1L, 8L)
    return(paste0(substr(call, 1L, max(1L, 40L - nchar(h) - 1L)), "_", h))
  }
  if (identical(model$provider, "openai") && nchar(id) > 40L) return(substr(id, 1L, 40L))
  id
}
build_openai_completions <- function(model, context, api_key, reasoning = NULL, max_tokens = NULL, temperature = NULL,
                                     compat = list(), session_id = NULL) {
  cp <- modifyList(list(supports_developer_role = TRUE, supports_store = TRUE, supports_reasoning_effort = TRUE,
    supports_usage_in_streaming = TRUE, max_tokens_field = "max_completion_tokens", requires_tool_result_name = FALSE,
    requires_assistant_after_tool_result = FALSE, requires_thinking_as_text = FALSE, thinking_format = "openai",
    supports_strict_mode = FALSE), compat)
  msgs <- transform_messages(context$messages, model, function(id, ...) openai_cc_id(id, model))
  out <- list()
  if (nzchar(context$system_prompt %||% "")) out[[1]] <- list(role = if (isTRUE(model$reasoning) && cp$supports_developer_role) "developer" else "system", content = context$system_prompt)
  last_role <- NULL; i <- 1L
  while (i <= length(msgs)) {
    m <- msgs[[i]]
    if (cp$requires_assistant_after_tool_result && identical(last_role, "tool_result") && m$role == "user")
      out[[length(out) + 1L]] <- list(role = "assistant", content = "I have processed the tool results.")
    if (m$role == "user") {
      if (is.character(m$content)) out[[length(out) + 1L]] <- list(role = "user", content = m$content)
      else {
        parts <- lapply(Filter(function(b) b$type != "text" || nzchar(b$text), m$content), function(b)
          if (b$type == "text") list(type = "text", text = b$text) else list(type = "image_url", image_url = list(url = sprintf("data:%s;base64,%s", b$mime_type, b$data))))
        if (length(parts)) out[[length(out) + 1L]] <- list(role = "user", content = parts)
      }
    } else if (m$role == "assistant") {
      texts <- Filter(function(b) b$type == "text" && nzchar(trimws(b$text)), m$content)
      thinks <- Filter(function(b) b$type == "thinking" && nzchar(trimws(b$thinking)), m$content)
      calls <- Filter(function(b) b$type == "tool_call", m$content)
      a <- list(role = "assistant", content = NULL)
      txt <- paste(vapply(texts, function(b) b$text, ""), collapse = "")
      if (length(thinks) && cp$requires_thinking_as_text) {
        txt <- paste0(paste(vapply(thinks, function(b) b$thinking, ""), collapse = "\n\n"), if (nzchar(txt)) "\n\n", txt)
      } else if (length(thinks)) {
        sig <- thinks[[1]]$thinking_signature
        if (!is.null(sig) && sig %in% c("reasoning", "reasoning_content", "reasoning_text")) a[[sig]] <- paste(vapply(thinks, function(b) b$thinking, ""), collapse = "\n")
      }
      if (nzchar(txt)) a$content <- txt
      if (length(calls)) a$tool_calls <- lapply(calls, function(tc) list(id = tc$id, type = "function",
        `function` = list(name = tc$name, arguments = as.character(jsonlite::toJSON(as_obj(tc$arguments), auto_unbox = TRUE, null = "null", digits = NA)))))
      if (is.null(a$content) && is.null(a$tool_calls)) { i <- i + 1L; next }
      if (is.null(a$content)) a["content"] <- list(NULL)
      out[[length(out) + 1L]] <- a
    } else if (m$role == "tool_result") {
      imgs <- list()
      while (i <= length(msgs) && msgs[[i]]$role == "tool_result") {
        r <- msgs[[i]]
        txt <- paste(vapply(Filter(function(b) b$type == "text", r$content), function(b) b$text, ""), collapse = "\n")
        has_img <- any(vapply(r$content, function(b) b$type == "image", NA))
        tm <- list(role = "tool", content = if (nzchar(txt)) txt else if (has_img) "(see attached image)" else "(no tool output)", tool_call_id = r$tool_call_id)
        if (cp$requires_tool_result_name) tm$name <- r$tool_name
        out[[length(out) + 1L]] <- tm
        for (b in Filter(function(b) b$type == "image", r$content)) imgs[[length(imgs) + 1L]] <- list(type = "image_url", image_url = list(url = sprintf("data:%s;base64,%s", b$mime_type, b$data)))
        i <- i + 1L
      }
      if (length(imgs)) { out[[length(out) + 1L]] <- list(role = "user", content = c(list(list(type = "text", text = "Attached image(s) from tool result:")), imgs)); last_role <- "user" }
      else last_role <- "tool_result"
      next
    }
    last_role <- m$role
    i <- i + 1L
  }
  body <- list(model = model$id, messages = out, stream = TRUE)
  if (cp$supports_usage_in_streaming) body$stream_options <- list(include_usage = TRUE)
  if (cp$supports_store) body$store <- FALSE
  if (!is.null(max_tokens)) body[[cp$max_tokens_field]] <- max_tokens
  if (!is.null(temperature)) body$temperature <- temperature
  tools <- context$tools %||% list()
  if (length(tools)) body$tools <- lapply(tools, function(t) list(type = "function", `function` = c(
    list(name = t$name, description = t$description, parameters = t$parameters), if (cp$supports_strict_mode) list(strict = FALSE))))
  level <- if (!is.null(reasoning)) clamp_thinking_level(model, reasoning) else NULL
  if (identical(level, "off")) level <- NULL
  if (isTRUE(model$reasoning)) {
    mapped <- if (!is.null(level)) model$thinking_level_map[[level]] %||% level else NULL
    switch(cp$thinking_format,
      openrouter = { body$reasoning <- list(effort = mapped %||% (model$thinking_level_map$off %||% "none")) },
      deepseek = { body$thinking <- list(type = if (is.null(level)) "disabled" else "enabled"); if (!is.null(level) && cp$supports_reasoning_effort) body$reasoning_effort <- mapped },
      zai = { body$thinking <- if (is.null(level)) list(type = "disabled") else list(type = "enabled", clear_thinking = FALSE) },
      qwen = { body$enable_thinking <- !is.null(level) },
      together = { body$reasoning <- list(enabled = !is.null(level)) },
      { if (!is.null(level) && cp$supports_reasoning_effort) body$reasoning_effort <- mapped })
  }
  headers <- list(authorization = paste("Bearer", api_key), "content-type" = "application/json", accept = "text/event-stream")
  list(url = paste0(sub("/+$", "", model$base_url), "/chat/completions"), headers = headers, body = body)
}

# ---- OpenAI Responses ----------------------------------------------------------------
responses_id_part <- function(x) sub("_+$", "", substr(gsub("[^a-zA-Z0-9_-]", "_", x), 1L, 64L))
build_openai_responses <- function(model, context, api_key, reasoning = NULL, max_tokens = NULL, session_id = NULL) {
  norm_id <- function(id, target, source) {
    if (!grepl("|", id, fixed = TRUE)) return(responses_id_part(id))
    p <- strsplit(id, "|", fixed = TRUE)[[1]]
    foreign <- !identical(source$provider, model$provider) || !identical(source$api, model$api)
    item <- if (foreign) paste0("fc_", short_hash(p[[2]])) else responses_id_part(p[[2]])
    if (!startsWith(item, "fc_")) item <- responses_id_part(paste0("fc_", item))
    paste0(responses_id_part(p[[1]]), "|", item)
  }
  msgs <- transform_messages(context$messages, model, norm_id)
  input <- list(); k <- 0L
  if (nzchar(context$system_prompt %||% "")) input[[1]] <- list(role = if (isTRUE(model$reasoning)) "developer" else "system", content = context$system_prompt)
  for (m in msgs) {
    if (m$role == "user") {
      content <- if (is.character(m$content)) list(list(type = "input_text", text = m$content)) else lapply(m$content, function(b)
        if (b$type == "text") list(type = "input_text", text = b$text) else list(type = "input_image", detail = "auto", image_url = sprintf("data:%s;base64,%s", b$mime_type, b$data)))
      input[[length(input) + 1L]] <- list(role = "user", content = content)
    } else if (m$role == "assistant") {
      same_pa <- identical(m$provider, model$provider) && identical(m$api, model$api)
      different_model <- same_pa && !identical(m$model, model$id)
      ti <- 0L
      for (b in m$content) {
        if (b$type == "thinking") {
          if (nzchar(b$thinking_signature %||% "")) input[[length(input) + 1L]] <- jsonlite::parse_json(b$thinking_signature, simplifyVector = FALSE)
        } else if (b$type == "text") {
          sig <- tryCatch(jsonlite::parse_json(b$text_signature %||% "null"), error = function(e) list(id = b$text_signature))
          id <- sig$id %||% (if (ti == 0L) sprintf("msg_gptr_%d", k) else sprintf("msg_gptr_%d_%d", k, ti))
          if (nchar(id) > 64L) id <- paste0("msg_", short_hash(id))
          ti <- ti + 1L
          item <- list(type = "message", role = "assistant", status = "completed", id = id,
            content = list(list(type = "output_text", text = b$text, annotations = list())))
          if (!is.null(sig$phase)) item$phase <- sig$phase
          input[[length(input) + 1L]] <- item
        } else if (b$type == "tool_call") {
          p <- strsplit(b$id, "|", fixed = TRUE)[[1]]
          item_id <- if (length(p) > 1L) p[[2]] else NULL
          if (!is.null(item_id) && (different_model || !startsWith(item_id, "fc_"))) item_id <- NULL
          fc <- list(type = "function_call", call_id = p[[1]], name = b$name,
            arguments = as.character(jsonlite::toJSON(as_obj(b$arguments), auto_unbox = TRUE, null = "null", digits = NA)))
          if (!is.null(item_id)) fc$id <- item_id
          input[[length(input) + 1L]] <- fc
        }
      }
    } else if (m$role == "tool_result") {
      txt <- paste(vapply(Filter(function(b) b$type == "text", m$content), function(b) b$text, ""), collapse = "\n")
      input[[length(input) + 1L]] <- list(type = "function_call_output", call_id = strsplit(m$tool_call_id, "|", fixed = TRUE)[[1]][[1]],
        output = if (nzchar(txt)) txt else "(no tool output)")
    }
    k <- k + 1L
  }
  body <- list(model = model$id, input = input, stream = TRUE, store = FALSE)
  if (!is.null(session_id)) body$prompt_cache_key <- substr(session_id, 1L, 64L)
  if (!is.null(max_tokens)) body$max_output_tokens <- max(max_tokens, 16L)
  tools <- context$tools %||% list()
  if (length(tools)) body$tools <- lapply(tools, function(t) list(type = "function", name = t$name, description = t$description, parameters = t$parameters, strict = FALSE))
  if (isTRUE(model$reasoning)) {
    level <- if (!is.null(reasoning)) clamp_thinking_level(model, reasoning) else "off"
    if (level != "off") {
      body$reasoning <- list(effort = model$thinking_level_map[[level]] %||% level, summary = "auto")
      body$include <- list("reasoning.encrypted_content")
    } else if (!("off" %in% names(model$thinking_level_map) && is.null(model$thinking_level_map$off))) {
      body$reasoning <- list(effort = model$thinking_level_map$off %||% "none")
    }
  }
  headers <- list(authorization = paste("Bearer", api_key), "content-type" = "application/json", accept = "text/event-stream")
  if (!is.null(session_id)) headers <- c(headers, list(session_id = session_id, "x-client-request-id" = session_id))
  list(url = paste0(sub("/+$", "", model$base_url), "/responses"), headers = headers, body = body)
}

# ---- Google Gemini ---------------------------------------------------------------------
gemini_major <- function(id) { m <- regmatches(tolower(id), regexec("^gemini(?:-live)?-(\\d+)", tolower(id), perl = TRUE))[[1]]; if (length(m) < 2L) NA_integer_ else as.integer(m[[2]]) }
uses_thinking_level <- function(id) grepl("gemini-3(\\.\\d+)?-(pro|flash)", tolower(id)) || tolower(id) %in% c("gemini-flash-latest", "gemini-flash-lite-latest") || grepl("gemma-?4", tolower(id))
build_google <- function(model, context, api_key, reasoning = NULL, max_tokens = NULL, temperature = NULL) {
  needs_id <- isTRUE(gemini_major(model$id) >= 3L)
  msgs <- transform_messages(context$messages, model, function(id, ...) if (needs_id) sanitize_id(id, 64L) else id)
  valid_sig <- function(s) is.character(s) && nzchar(s) && nchar(s) %% 4L == 0L && grepl("^[A-Za-z0-9+/]+={0,2}$", s)
  contents <- list()
  for (m in msgs) {
    if (m$role == "user") {
      parts <- if (is.character(m$content)) list(list(text = m$content)) else lapply(m$content, function(b)
        if (b$type == "text") list(text = b$text) else list(inlineData = list(mimeType = b$mime_type, data = b$data)))
      if (length(parts)) contents[[length(contents) + 1L]] <- list(role = "user", parts = parts)
    } else if (m$role == "assistant") {
      same <- identical(m$provider, model$provider) && identical(m$model, model$id)
      parts <- list()
      for (b in m$content) {
        if (b$type == "text") {
          sig <- if (same && valid_sig(b$text_signature)) b$text_signature else NULL
          if (!nzchar(trimws(b$text)) && is.null(sig)) next
          parts[[length(parts) + 1L]] <- c(list(text = b$text), if (!is.null(sig)) list(thoughtSignature = sig))
        } else if (b$type == "thinking") {
          sig <- if (same && valid_sig(b$thinking_signature)) b$thinking_signature else NULL
          if (!nzchar(trimws(b$thinking)) && is.null(sig)) next
          parts[[length(parts) + 1L]] <- if (same) c(list(thought = TRUE, text = b$thinking), if (!is.null(sig)) list(thoughtSignature = sig)) else list(text = b$thinking)
        } else if (b$type == "tool_call") {
          sig <- if (same && valid_sig(b$thought_signature)) b$thought_signature else NULL
          parts[[length(parts) + 1L]] <- c(list(functionCall = c(list(name = b$name, args = as_obj(b$arguments)), if (needs_id) list(id = b$id))),
                                           if (!is.null(sig)) list(thoughtSignature = sig))
        }
      }
      if (length(parts)) contents[[length(contents) + 1L]] <- list(role = "model", parts = parts)
    } else if (m$role == "tool_result") {
      txt <- paste(vapply(Filter(function(b) b$type == "text", m$content), function(b) b$text, ""), collapse = "\n")
      fr <- list(functionResponse = c(list(name = m$tool_name, response = if (isTRUE(m$is_error)) list(error = txt) else list(output = txt)), if (needs_id) list(id = m$tool_call_id)))
      last <- if (length(contents)) contents[[length(contents)]] else NULL
      if (!is.null(last) && last$role == "user" && any(vapply(last$parts, function(p) !is.null(p$functionResponse), NA))) {
        contents[[length(contents)]]$parts[[length(last$parts) + 1L]] <- fr          # all results of a turn in ONE user content
      } else contents[[length(contents) + 1L]] <- list(role = "user", parts = list(fr))
    }
  }
  gen <- list()
  if (!is.null(temperature)) gen$temperature <- temperature
  if (!is.null(max_tokens)) gen$maxOutputTokens <- max_tokens
  if (isTRUE(model$reasoning)) {
    level <- if (!is.null(reasoning)) clamp_thinking_level(model, reasoning) else "off"
    if (level != "off") {
      resolved <- tolower(model$thinking_level_map[[level]] %||% level)
      gen$thinkingConfig <- if (uses_thinking_level(model$id)) list(includeThoughts = TRUE, thinkingLevel = toupper(resolved))
                            else list(includeThoughts = TRUE, thinkingBudget = -1L)
    } else if (!uses_thinking_level(model$id)) gen$thinkingConfig <- list(thinkingBudget = 0L)
  }
  body <- list(contents = contents)
  if (nzchar(context$system_prompt %||% "")) body$systemInstruction <- list(parts = list(list(text = context$system_prompt)))
  tools <- context$tools %||% list()
  if (length(tools)) body$tools <- list(list(functionDeclarations = lapply(tools, function(t) list(name = t$name, description = t$description, parametersJsonSchema = t$parameters))))
  if (length(gen)) body$generationConfig <- gen
  list(url = sprintf("%s/models/%s:streamGenerateContent?alt=sse", sub("/+$", "", model$base_url), model$id),
       headers = list("x-goog-api-key" = api_key, "content-type" = "application/json"), body = body)
}

to_json <- function(x, pretty = FALSE) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, pretty = pretty))
```

Test script `test_messages.R`:

```r
suppressPackageStartupMessages(library(jsonlite))
source("R/messages.R")

tools <- list(
  list(name = "r_eval", description = "Evaluate R code in the live session",
       parameters = list(type = "object", properties = list(code = list(type = "string", description = "R code")), required = list("code"))),
  list(name = "ls_env", description = "List objects in the session",
       parameters = list(type = "object", properties = empty_obj(), required = list()))
)
usage0 <- list(input = 0, output = 0, cache_read = 0, cache_write = 0, total_tokens = 0, cost = list(total = 0))
convo <- list(
  user_message("Mean mpg by cyl, then plot it."),
  list(role = "assistant", api = "anthropic-messages", provider = "anthropic", model = "claude-opus-5-5",
       stop_reason = "toolUse", usage = usage0, timestamp = 1,
       content = list(
         list(type = "thinking", thinking = "mtcars is loaded; aggregate.", thinking_signature = "EqQBCgIYAhIM1gbc"),
         list(type = "text", text = "Computing."),
         list(type = "tool_call", id = "toolu_01T1x1fJ34qAmk2tNTrN7Up6", name = "r_eval", arguments = list(code = "aggregate(mpg ~ cyl, mtcars, mean)")))),
  tool_result_message("toolu_01T1x1fJ34qAmk2tNTrN7Up6", "r_eval", "  cyl  mpg\n1   4 26.7\n2   6 19.7\n3   8 15.1"),
  list(role = "assistant", api = "openai-responses", provider = "openai", model = "gpt-5.5",
       stop_reason = "toolUse", usage = usage0, timestamp = 2,
       content = list(
         list(type = "thinking", thinking = "Plan the plot", thinking_signature = '{"id":"rs_1","type":"reasoning","encrypted_content":"gAAAA==","summary":[{"type":"summary_text","text":"Plan the plot"}]}'),
         list(type = "text", text = "Plotting now.", text_signature = '{"v":1,"id":"msg_abc","phase":"commentary"}'),
         list(type = "tool_call", id = "call_9Zx8Yw7Vu6|fc_0a1b2c+/=", name = "r_eval", arguments = list(code = "plot(1)")),
         list(type = "tool_call", id = "call_second|fc_second", name = "ls_env", arguments = empty_obj()))),
  tool_result_message("call_9Zx8Yw7Vu6|fc_0a1b2c+/=", "r_eval", list(text_block("plot created"), image_block("iVBORw0KGgo=", "image/png"))),
  # (no result for call_second: orphaned)
  user_message("Stop, use ggplot2 instead."),
  list(role = "assistant", api = "anthropic-messages", provider = "anthropic", model = "claude-opus-5-5",
       stop_reason = "aborted", error_message = "Request was aborted", usage = usage0, timestamp = 3,
       content = list(list(type = "text", text = "Sure, I wi"))),
  user_message("Go on.")
)
ctx <- list(system_prompt = "You are gptr, an agent living inside an R session.", messages = convo, tools = tools)

m_anthropic <- list(id = "claude-opus-5-5", api = "anthropic-messages", provider = "anthropic", base_url = "https://api.anthropic.com",
  reasoning = TRUE, input = c("text", "image"), max_tokens = 128000,
  thinking_level_map = list(off = NULL, minimal = NULL, low = "low", medium = "medium", high = "high", xhigh = "xhigh", max = "max"),
  compat = list(force_adaptive_thinking = TRUE, supports_temperature = FALSE))
m_haiku <- list(id = "claude-haiku-4-5", api = "anthropic-messages", provider = "anthropic", base_url = "https://api.anthropic.com",
  reasoning = TRUE, input = c("text", "image"), max_tokens = 64000)
m_groq <- list(id = "openai/gpt-oss-120b", api = "openai-completions", provider = "groq", base_url = "https://api.groq.com/openai/v1",
  reasoning = TRUE, input = "text", max_tokens = 32768)
m_openai <- list(id = "gpt-5.5", api = "openai-responses", provider = "openai", base_url = "https://api.openai.com/v1",
  reasoning = TRUE, input = c("text", "image"), max_tokens = 128000, thinking_level_map = list(off = "none", minimal = NULL, xhigh = "xhigh"))
m_gemini <- list(id = "gemini-3.5-flash", api = "google-generative-ai", provider = "google",
  base_url = "https://generativelanguage.googleapis.com/v1beta", reasoning = TRUE, input = c("text", "image"), max_tokens = 65536)

cat("== transform_messages(target = groq/openai-completions) ==\n")
tm <- transform_messages(convo, m_groq, function(id, ...) openai_cc_id(id, m_groq))
for (m in tm) {
  desc <- switch(m$role,
    user = if (is.character(m$content)) m$content else paste(vapply(m$content, function(b) b$type, ""), collapse = "+"),
    assistant = paste(vapply(m$content, function(b) if (b$type == "tool_call") sprintf("tool_call(%s)", b$id) else sprintf("%s(%s)", b$type, substr(b$text %||% b$thinking, 1, 28)), ""), collapse = " | "),
    tool_result = sprintf("-> %s error=%s: %s", m$tool_call_id, m$is_error, paste(vapply(m$content, function(b) b$text %||% "<image>", ""), collapse = " ")))
  cat(sprintf("  %-12s %s\n", m$role, gsub("\n", "\\\\n", desc)))
}
stopifnot(length(tm) == 8L)                                             # aborted assistant dropped, synthetic result added
stopifnot(tm[[6]]$role == "tool_result", isTRUE(tm[[6]]$is_error), tm[[6]]$content[[1]]$text == "No result provided")
stopifnot(all(vapply(tm[[2]]$content, function(b) b$type, "") == c("text", "text", "tool_call")))   # foreign thinking -> plain text

cat("\n== thinking level clamping ==\n")
cat("  opus-5-5 supports:", paste(supported_thinking_levels(m_anthropic), collapse = ","), "| 'minimal' ->", clamp_thinking_level(m_anthropic, "minimal"), "| 'off' ->", clamp_thinking_level(m_anthropic, "off"), "\n")
cat("  gpt-5.5  supports:", paste(supported_thinking_levels(m_openai), collapse = ","), "| 'max' ->", clamp_thinking_level(m_openai, "max"), "| 'minimal' ->", clamp_thinking_level(m_openai, "minimal"), "\n")
cat("  haiku    supports:", paste(supported_thinking_levels(m_haiku), collapse = ","), "| 'xhigh' ->", clamp_thinking_level(m_haiku, "xhigh"), "\n")

show <- function(title, req) {
  cat("\n==", title, "==\n")
  cat("  POST", req$url, "\n")
  h <- req$headers; for (k in intersect(names(h), c("x-api-key", "authorization", "x-goog-api-key"))) h[[k]] <- "<redacted>"
  cat("  headers:", to_json(h), "\n")
  js <- to_json(req$body, pretty = TRUE)
  stopifnot(jsonlite::validate(js))
  cat(js, "\n")
  invisible(req)
}
a <- show("Anthropic (adaptive thinking model, reasoning = 'high')", build_anthropic(m_anthropic, ctx, "sk-ant-demo", reasoning = "high"))
stopifnot(identical(a$body$thinking$type, "adaptive"), identical(a$body$output_config$effort, "high"))
stopifnot(a$body$messages[[2]]$content[[1]]$type == "thinking")              # own signed thinking replayed
stopifnot(length(a$body$messages[[5]]$content) == 2L)                        # two tool_results merged into ONE user message
h <- build_anthropic(m_haiku, ctx, "sk-ant-demo", reasoning = "medium", max_tokens = 8000)
cat("\n  budget model (haiku-4-5, medium, max_tokens 8000): thinking =", to_json(h$body$thinking), " max_tokens =", h$body$max_tokens, " beta =", h$headers[["anthropic-beta"]], "\n")

g <- show("OpenAI-compatible Chat Completions (Groq)", build_openai_completions(m_groq, ctx, "gsk-demo", reasoning = "low", max_tokens = 4096,
  compat = list(supports_store = FALSE, supports_developer_role = FALSE, max_tokens_field = "max_tokens")))
ids <- unlist(lapply(g$body$messages, function(m) c(m$tool_call_id, vapply(m$tool_calls %||% list(), function(t) t$id, ""))))
cat("  tool ids on the wire:", paste(unique(ids), collapse = ", "), " (all <= 40 chars:", all(nchar(ids) <= 40), ")\n")
stopifnot(all(grepl("^[A-Za-z0-9_-]+$", ids)))

o <- show("OpenAI Responses", build_openai_responses(m_openai, ctx, "sk-demo", reasoning = "high", session_id = "sess-123"))
types <- vapply(o$body$input, function(x) x$type %||% x$role, "")
cat("  input item sequence:", paste(types, collapse = " "), "\n")

ge <- show("Google Gemini", build_google(m_gemini, ctx, "AIza-demo", reasoning = "medium", max_tokens = 8192))
stopifnot(identical(ge$body$generationConfig$thinkingConfig$thinkingLevel, "MEDIUM"))
cat("\nALL MESSAGE CHECKS PASSED\n")
```

Observed output (first 14 lines, then the summary lines; the full output
prints four request bodies, 632 lines, all of which passed
`jsonlite::validate()`):

```
== transform_messages(target = groq/openai-completions) ==
  user         Mean mpg by cyl, then plot it.
  assistant    text(mtcars is loaded; aggregate.) | text(Computing.) | tool_call(toolu_01T1x1fJ34qAmk2tNTrN7Up6)
  tool_result  -> toolu_01T1x1fJ34qAmk2tNTrN7Up6 error=FALSE:   cyl  mpg\n1   4 26.7\n2   6 19.7\n3   8 15.1
  assistant    text(Plan the plot) | text(Plotting now.) | tool_call(call_9Zx8Yw7Vu6_fc_0a1b2c___) | tool_call(call_second_fc_second)
  tool_result  -> call_9Zx8Yw7Vu6_fc_0a1b2c___ error=FALSE: plot created (tool image omitted: model does not support images)
  tool_result  -> call_second_fc_second error=TRUE: No result provided
  user         Stop, use ggplot2 instead.
  user         Go on.

== thinking level clamping ==
  opus-5-5 supports: low,medium,high,xhigh,max | 'minimal' -> low | 'off' -> low 
  gpt-5.5  supports: off,low,medium,high,xhigh | 'max' -> xhigh | 'minimal' -> low 
  haiku    supports: off,minimal,low,medium,high | 'xhigh' -> high 
...
  budget model (haiku-4-5, medium, max_tokens 8000): thinking = {"type":"enabled","budget_tokens":8192,"display":"summarized"}  max_tokens = 16192  beta = interleaved-thinking-2025-05-14 
  tool ids on the wire: toolu_01T1x1fJ34qAmk2tNTrN7Up6, call_9Zx8Yw7Vu6_fc_0a1b2c___, call_second_fc_second  (all <= 40 chars: TRUE )
  input item sequence: developer user message message function_call function_call_output reasoning message function_call function_call function_call_output function_call_output user user 
ALL MESSAGE CHECKS PASSED
```

All four bodies were inspected manually: consecutive tool results are merged
into one user message (Anthropic, Gemini), the orphaned call gets
`"No result provided"` with `is_error: true`, the aborted assistant turn is
absent, foreign thinking is plain text, ids are within the limits. These
request bodies were **not** sent to the vendors. The complete Anthropic
request printed by this run (lines 16-183 of the output):

```
== Anthropic (adaptive thinking model, reasoning = 'high') ==
  POST https://api.anthropic.com/v1/messages 
  headers: {"x-api-key":"<redacted>","anthropic-version":"2023-06-01","content-type":"application/json","accept":"text/event-stream"} 
{
  "model": "claude-opus-5-5",
  "messages": [
    {
      "role": "user",
      "content": "Mean mpg by cyl, then plot it."
    },
    {
      "role": "assistant",
      "content": [
        {
          "type": "thinking",
          "thinking": "mtcars is loaded; aggregate.",
          "signature": "EqQBCgIYAhIM1gbc"
        },
        {
          "type": "text",
          "text": "Computing."
        },
        {
          "type": "tool_use",
          "id": "toolu_01T1x1fJ34qAmk2tNTrN7Up6",
          "name": "r_eval",
          "input": {
            "code": "aggregate(mpg ~ cyl, mtcars, mean)"
          }
        }
      ]
    },
    {
      "role": "user",
      "content": [
        {
          "type": "tool_result",
          "tool_use_id": "toolu_01T1x1fJ34qAmk2tNTrN7Up6",
          "content": "  cyl  mpg\n1   4 26.7\n2   6 19.7\n3   8 15.1",
          "is_error": false
        }
      ]
    },
    {
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "Plan the plot"
        },
        {
          "type": "text",
          "text": "Plotting now."
        },
        {
          "type": "tool_use",
          "id": "call_9Zx8Yw7Vu6_fc_0a1b2c___",
          "name": "r_eval",
          "input": {
            "code": "plot(1)"
          }
        },
        {
          "type": "tool_use",
          "id": "call_second_fc_second",
          "name": "ls_env",
          "input": {}
        }
      ]
    },
    {
      "role": "user",
      "content": [
        {
          "type": "tool_result",
          "tool_use_id": "call_9Zx8Yw7Vu6_fc_0a1b2c___",
          "content": [
            {
              "type": "text",
              "text": "plot created"
            },
            {
              "type": "image",
              "source": {
                "type": "base64",
                "media_type": "image/png",
                "data": "iVBORw0KGgo="
              }
            }
          ],
          "is_error": false
        },
        {
          "type": "tool_result",
          "tool_use_id": "call_second_fc_second",
          "content": "No result provided",
          "is_error": true
        }
      ]
    },
    {
      "role": "user",
      "content": "Stop, use ggplot2 instead."
    },
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "Go on.",
          "cache_control": {
            "type": "ephemeral"
          }
        }
      ]
    }
  ],
  "max_tokens": 128000,
  "stream": true,
  "system": [
    {
      "type": "text",
      "text": "You are gptr, an agent living inside an R session.",
      "cache_control": {
        "type": "ephemeral"
      }
    }
  ],
  "tools": [
    {
      "name": "r_eval",
      "description": "Evaluate R code in the live session",
      "eager_input_streaming": true,
      "input_schema": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string",
            "description": "R code"
          }
        },
        "required": [
          "code"
        ]
      }
    },
    {
      "name": "ls_env",
      "description": "List objects in the session",
      "eager_input_streaming": true,
      "input_schema": {
        "type": "object",
        "properties": {},
        "required": []
      },
      "cache_control": {
        "type": "ephemeral"
      }
    }
  ],
  "thinking": {
    "type": "adaptive",
    "display": "summarized"
  },
  "output_config": {
    "effort": "high"
  }
} 
```

The complete OpenAI Responses request printed by the same run (lines 303-468):

```
== OpenAI Responses ==
  POST https://api.openai.com/v1/responses 
  headers: {"authorization":"<redacted>","content-type":"application/json","accept":"text/event-stream","session_id":"sess-123","x-client-request-id":"sess-123"} 
{
  "model": "gpt-5.5",
  "input": [
    {
      "role": "developer",
      "content": "You are gptr, an agent living inside an R session."
    },
    {
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "Mean mpg by cyl, then plot it."
        }
      ]
    },
    {
      "type": "message",
      "role": "assistant",
      "status": "completed",
      "id": "msg_gptr_1",
      "content": [
        {
          "type": "output_text",
          "text": "mtcars is loaded; aggregate.",
          "annotations": []
        }
      ]
    },
    {
      "type": "message",
      "role": "assistant",
      "status": "completed",
      "id": "msg_gptr_1_1",
      "content": [
        {
          "type": "output_text",
          "text": "Computing.",
          "annotations": []
        }
      ]
    },
    {
      "type": "function_call",
      "call_id": "toolu_01T1x1fJ34qAmk2tNTrN7Up6",
      "name": "r_eval",
      "arguments": "{\"code\":\"aggregate(mpg ~ cyl, mtcars, mean)\"}"
    },
    {
      "type": "function_call_output",
      "call_id": "toolu_01T1x1fJ34qAmk2tNTrN7Up6",
      "output": "  cyl  mpg\n1   4 26.7\n2   6 19.7\n3   8 15.1"
    },
    {
      "id": "rs_1",
      "type": "reasoning",
      "encrypted_content": "gAAAA==",
      "summary": [
        {
          "type": "summary_text",
          "text": "Plan the plot"
        }
      ]
    },
    {
      "type": "message",
      "role": "assistant",
      "status": "completed",
      "id": "msg_abc",
      "content": [
        {
          "type": "output_text",
          "text": "Plotting now.",
          "annotations": []
        }
      ],
      "phase": "commentary"
    },
    {
      "type": "function_call",
      "call_id": "call_9Zx8Yw7Vu6",
      "name": "r_eval",
      "arguments": "{\"code\":\"plot(1)\"}",
      "id": "fc_0a1b2c+/="
    },
    {
      "type": "function_call",
      "call_id": "call_second",
      "name": "ls_env",
      "arguments": "{}",
      "id": "fc_second"
    },
    {
      "type": "function_call_output",
      "call_id": "call_9Zx8Yw7Vu6",
      "output": "plot created"
    },
    {
      "type": "function_call_output",
      "call_id": "call_second",
      "output": "No result provided"
    },
    {
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "Stop, use ggplot2 instead."
        }
      ]
    },
    {
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "Go on."
        }
      ]
    }
  ],
  "stream": true,
  "store": false,
  "prompt_cache_key": "sess-123",
  "tools": [
    {
      "type": "function",
      "name": "r_eval",
      "description": "Evaluate R code in the live session",
      "parameters": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string",
            "description": "R code"
          }
        },
        "required": [
          "code"
        ]
      },
      "strict": false
    },
    {
      "type": "function",
      "name": "ls_env",
      "description": "List objects in the session",
      "parameters": {
        "type": "object",
        "properties": {},
        "required": []
      },
      "strict": false
    }
  ],
  "reasoning": {
    "effort": "high",
    "summary": "auto"
  },
  "include": [
    "reasoning.encrypted_content"
  ]
} 
```

### 5.6 OAuth building blocks - `R/oauth.R`

```r
# OAuth building blocks in pure R (openssl + httr2 + httpuv + jsonlite).

`%||%` <- function(a, b) if (is.null(a)) b else a

base64url_encode <- function(bytes) {
  x <- openssl::base64_encode(bytes)
  x <- gsub("=+$", "", x)
  chartr("+/", "-_", x)
}
base64url_decode <- function(x) {
  x <- chartr("-_", "+/", x)
  pad <- (4L - nchar(x) %% 4L) %% 4L
  openssl::base64_decode(paste0(x, strrep("=", pad)))
}

# RFC 7636 (S256). 32 random bytes -> 43 char verifier.
pkce_generate <- function(verifier = NULL) {
  if (is.null(verifier)) verifier <- base64url_encode(openssl::rand_bytes(32))
  challenge <- base64url_encode(openssl::sha256(charToRaw(verifier)))
  list(verifier = verifier, challenge = challenge, method = "S256")
}

random_state <- function(n = 16) paste(as.character(openssl::rand_bytes(n)), collapse = "")

jwt_payload <- function(token) {
  parts <- strsplit(token, ".", fixed = TRUE)[[1]]
  if (length(parts) != 3L) return(NULL)
  tryCatch(jsonlite::parse_json(rawToChar(base64url_decode(parts[[2]]))), error = function(e) NULL)
}

# Accepts a full redirect URL, "code#state", a query string, or a bare code.
parse_authorization_input <- function(input) {
  value <- trimws(input)
  if (!nzchar(value)) return(list())
  if (grepl("^https?://", value)) {
    q <- httr2::url_parse(value)$query
    return(list(code = q$code, state = q$state))
  }
  if (grepl("#", value, fixed = TRUE)) {
    p <- strsplit(value, "#", fixed = TRUE)[[1]]
    return(list(code = p[[1]], state = if (length(p) > 1L) p[[2]] else NULL))
  }
  if (grepl("code=", value, fixed = TRUE)) {
    q <- httr2::url_parse(paste0("http://x/?", sub("^\\?", "", value)))$query
    return(list(code = q$code, state = q$state))
  }
  list(code = value)
}

# Loopback redirect receiver. Returns immediately; poll $result() while calling
# later::run_now() / httpuv::service(). port = 0 picks a free port.
oauth_callback_server <- function(path = "/callback", state = NULL, host = "127.0.0.1", port = 0L,
                                  provider_name = "provider") {
  if (identical(as.integer(port), 0L)) port <- httpuv::randomPort(host = host)
  result <- NULL
  page <- function(status, msg) list(status = status,
    headers = list("Content-Type" = "text/html; charset=utf-8", "Cache-Control" = "no-store"),
    body = sprintf("<!doctype html><meta charset='utf-8'><title>gptr</title><p>%s</p>", msg))
  app <- list(call = function(req) {
    if (!identical(req$REQUEST_METHOD, "GET") || !identical(req$PATH_INFO, path)) return(page(404L, "Callback route not found."))
    q <- httr2::url_parse(paste0("http://x/", req$QUERY_STRING %||% ""))$query
    if (!is.null(state) && !identical(q$state, state)) return(page(400L, "State mismatch."))
    if (!is.null(result)) return(page(409L, "This sign-in has already been handled."))
    if (!is.null(q$error)) {
      result <<- list(error = q$error_description %||% q$error)
      return(page(400L, sprintf("%s authorization failed.", provider_name)))
    }
    if (is.null(q$code)) return(page(400L, "Missing authorization code."))
    result <<- list(code = q$code, state = q$state, query = q)
    page(200L, sprintf("Signed in to %s. You may now close this page.", provider_name))
  })
  srv <- httpuv::startServer(host, port, app)
  list(
    redirect_uri = sprintf("http://%s:%d%s", if (grepl(":", host, fixed = TRUE)) paste0("[", host, "]") else host, port, path),
    port = port,
    result = function() result,
    wait = function(timeout = 300, poll = 0.05, interrupt_check = NULL) {
      deadline <- Sys.time() + timeout
      while (is.null(result) && Sys.time() < deadline) {
        httpuv::service(as.integer(poll * 1000))
        if (!is.null(interrupt_check) && isTRUE(interrupt_check())) break
      }
      result
    },
    close = function() tryCatch(httpuv::stopServer(srv), error = function(e) NULL)
  )
}

# RFC 8628 device-code polling (port of Pi's pollOAuthDeviceCodeFlow).
# `poll` returns list(status = "pending" | "slow_down" | "failed" | "complete", ...).
oauth_device_poll <- function(poll, interval = 5, expires_in = Inf, wait_before_first_poll = FALSE,
                              sleep = Sys.sleep, now = function() as.numeric(Sys.time())) {
  deadline <- now() + expires_in
  interval <- max(1, interval %||% 5)
  slow_downs <- 0L
  if (wait_before_first_poll) sleep(min(interval, max(0, deadline - now())))
  while (now() < deadline) {
    res <- poll()
    if (identical(res$status, "complete")) return(res$value)
    if (identical(res$status, "failed")) stop(res$message, call. = FALSE)
    if (identical(res$status, "slow_down")) {
      slow_downs <- slow_downs + 1L
      interval <- if (is.numeric(res$interval) && is.finite(res$interval) && res$interval > 0) max(1, res$interval) else max(1, interval + 5)
    }
    remaining <- deadline - now()
    if (remaining <= 0) break
    sleep(min(interval, remaining))
  }
  stop(if (slow_downs > 0L) "Device flow timed out after one or more slow_down responses (check the system clock)." else "Device flow timed out", call. = FALSE)
}

# --- credential store: one JSON file, one entry per provider --------------------
# Shape (identical to Pi's auth.json):
#   { "openrouter": {"type":"api_key","key":"..."},
#     "github-copilot": {"type":"oauth","access":"...","refresh":"...","expires":1759100000000, ...} }
credential_store <- function(path) {
  lock_dir <- paste0(path, ".lock")
  with_lock <- function(fn, timeout = 30, stale = 30) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
    t0 <- Sys.time()
    repeat {
      if (dir.create(lock_dir, showWarnings = FALSE)) break          # mkdir is atomic on every OS
      age <- as.numeric(difftime(Sys.time(), file.info(lock_dir)$mtime, units = "secs"))
      if (!is.na(age) && age > stale) { unlink(lock_dir, recursive = TRUE, force = TRUE); next }
      if (as.numeric(difftime(Sys.time(), t0, units = "secs")) > timeout) stop("Could not lock credential store: ", path)
      Sys.sleep(0.02 + stats::runif(1, 0, 0.03))
    }
    on.exit(unlink(lock_dir, recursive = TRUE, force = TRUE), add = TRUE)
    fn()
  }
  read_all <- function() {
    if (!file.exists(path)) return(structure(list(), names = character(0)))
    txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    txt <- sub("^﻿", "", txt)
    if (!nzchar(trimws(txt))) return(structure(list(), names = character(0)))
    jsonlite::parse_json(txt, simplifyVector = FALSE)
  }
  write_all <- function(data) {
    tmp <- paste0(path, ".tmp-", Sys.getpid())
    old <- Sys.umask("077"); on.exit(Sys.umask(old), add = TRUE)
    con <- file(tmp, open = "wb")
    writeLines(enc2utf8(as.character(jsonlite::toJSON(data, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE))), con, useBytes = TRUE)
    close(con)
    Sys.chmod(tmp, "0600", use_umask = FALSE)
    if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
    invisible(TRUE)
  }
  list(
    path = path,
    read = function(provider) read_all()[[provider]],
    list = function() { d <- read_all(); lapply(names(d), function(n) list(provider = n, type = d[[n]]$type)) },
    # the only write path: fn(current) -> new credential, or NULL to leave unchanged
    modify = function(provider, fn) with_lock(function() {
      d <- read_all()
      nxt <- fn(d[[provider]])
      if (is.null(nxt)) return(d[[provider]])
      d[[provider]] <- nxt
      write_all(d)
      nxt
    }),
    delete = function(provider) with_lock(function() { d <- read_all(); d[[provider]] <- NULL; write_all(d); invisible(NULL) })
  )
}

# Double-checked refresh (port of Pi resolveStoredOAuth): refresh when less than
# `min_validity` seconds remain; the expiry re-check and refresh run under the lock.
oauth_resolve <- function(store, provider, refresh_fn, min_validity = 300, now = function() as.numeric(Sys.time()) * 1000) {
  cred <- store$read(provider)
  if (is.null(cred) || !identical(cred$type, "oauth")) return(NULL)
  soon <- function(c) now() + min_validity * 1000 >= c$expires
  if (soon(cred)) {
    cred <- store$modify(provider, function(current) {
      if (is.null(current) || !identical(current$type, "oauth")) return(NULL)   # logged out meanwhile
      if (!soon(current)) return(NULL)                                         # someone else refreshed
      refresh_fn(current)
    })
  }
  cred
}
```

Test script `test_oauth.R` (local mock authorization server that verifies the
PKCE challenge; "browser" simulated by a background process):

```r
suppressPackageStartupMessages({ library(httr2); library(jsonlite) })
source("R/oauth.R")

cat("== PKCE against the RFC 7636 appendix B vector ==\n")
p <- pkce_generate("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
cat("  challenge:", p$challenge, " matches RFC:", identical(p$challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"), "\n")
q <- pkce_generate()
cat("  random verifier length:", nchar(q$verifier), " charset ok:", grepl("^[A-Za-z0-9_-]{43}$", q$verifier), "\n")

cat("\n== JWT claim extraction (fabricated, unsigned token) ==\n")
claims <- list(exp = 1759100000, "https://api.openai.com/auth" = list(chatgpt_account_id = "acct_demo_123", chatgpt_plan_type = "plus"))
tok <- paste(base64url_encode(charToRaw('{"alg":"none"}')), base64url_encode(charToRaw(as.character(toJSON(claims, auto_unbox = TRUE)))), "sig", sep = ".")
cat("  account id:", jwt_payload(tok)[["https://api.openai.com/auth"]]$chatgpt_account_id, "\n")

cat("\n== manual paste parsing ==\n")
for (x in c("http://localhost:53692/callback?code=abc123&state=xyz", "abc123#xyz", "code=abc123&state=xyz", "abc123")) {
  r <- parse_authorization_input(x)
  cat(sprintf("  %-55s -> code=%s state=%s\n", x, r$code %||% "NULL", r$state %||% "NULL"))
}

# ---- mock authorization server (background process) -------------------------------
mock_port <- httpuv::randomPort()
mock <- callr::r_bg(function(port) {
  polls <- 0L
  challenge <- NULL
  b64url <- function(bytes) chartr("+/", "-_", gsub("=+$", "", openssl::base64_encode(bytes)))
  json <- function(status, x) list(status = status, headers = list("Content-Type" = "application/json"),
                                   body = as.character(jsonlite::toJSON(x, auto_unbox = TRUE)))
  form <- function(txt) { kv <- strsplit(strsplit(txt, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
    stats::setNames(lapply(kv, function(p) utils::URLdecode(gsub("+", " ", p[[2]], fixed = TRUE))), vapply(kv, `[[`, "", 1)) }
  app <- list(call = function(req) {
    body <- rawToChar(req$rook.input$read())
    path <- req$PATH_INFO
    if (path == "/register_challenge") { challenge <<- sub("^\\?c=", "", req$QUERY_STRING); return(json(200L, list(ok = TRUE))) }
    if (path == "/token") {
      f <- if (grepl("json", req$CONTENT_TYPE %||% "")) jsonlite::parse_json(body) else form(body)
      if (identical(f$grant_type, "authorization_code")) {
        ok <- identical(f$code, "good-code") && identical(b64url(openssl::sha256(charToRaw(f$code_verifier))), challenge)
        if (!ok) return(json(400L, list(error = "invalid_grant", error_description = "PKCE verification failed")))
        return(json(200L, list(access_token = "access-1", refresh_token = "refresh-1", expires_in = 3600, scope = "inference")))
      }
      if (identical(f$grant_type, "refresh_token")) {
        if (!identical(f$refresh_token, "refresh-1")) return(json(400L, list(error = "invalid_grant")))
        return(json(200L, list(access_token = "access-2", refresh_token = "refresh-2", expires_in = 3600)))
      }
      if (identical(f$grant_type, "urn:ietf:params:oauth:grant-type:device_code")) {
        polls <<- polls + 1L
        if (polls == 1L) return(json(400L, list(error = "authorization_pending")))
        if (polls == 2L) return(json(400L, list(error = "slow_down", interval = 2)))
        if (polls == 3L) return(json(400L, list(error = "authorization_pending")))
        return(json(200L, list(access_token = "device-access", refresh_token = "device-refresh", expires_in = 28800)))
      }
    }
    if (path == "/device/code") return(json(200L, list(device_code = "dev-1", user_code = "WDJB-MJHT",
      verification_uri = "https://example.com/device", interval = 1, expires_in = 900)))
    json(404L, list(error = "not_found"))
  })
  `%||%` <- function(a, b) if (is.null(a)) b else a
  srv <- httpuv::startServer("127.0.0.1", port, app)
  t0 <- Sys.time()
  while (difftime(Sys.time(), t0, units = "secs") < 40) httpuv::service(100)
}, args = list(port = mock_port))
on.exit(mock$kill(), add = TRUE)
# wait until the mock listens (httpuv accepts many connections, so probing is safe)
# (Verifier fix: the original fixed Sys.sleep(1) raced the child's start-up and
# failed 2 of 6 runs under concurrent load with "Could not connect to server".)
for (i in 1:300) {
  up <- tryCatch({ con <- socketConnection("127.0.0.1", mock_port, open = "r+b", timeout = 1); close(con); TRUE },
                 error = function(e) FALSE, warning = function(w) FALSE)
  if (up) break
  if (!mock$is_alive()) stop("mock server died: ", mock$read_all_error())
  Sys.sleep(0.1)
}
if (!up) stop("mock server did not start within 30 s")
base <- sprintf("http://127.0.0.1:%d", mock_port)

post <- function(url, fields, as = c("form", "json")) {
  as <- match.arg(as)
  req <- request(url) |> req_headers(Accept = "application/json") |> req_error(is_error = function(r) FALSE) |> req_timeout(30)
  req <- if (as == "form") do.call(req_body_form, c(list(req), fields)) else req_body_json(req, fields)
  resp <- req_perform(req)
  list(ok = resp_status(resp) < 400L, status = resp_status(resp), body = tryCatch(resp_body_json(resp), error = function(e) list()))
}
to_credential <- function(tok, skew = 300) list(type = "oauth", access = tok$access_token, refresh = tok$refresh_token,
  expires = round(as.numeric(Sys.time()) * 1000 + tok$expires_in * 1000 - skew * 1000))

cat("\n== authorization-code + PKCE with loopback callback ==\n")
pk <- pkce_generate(); st <- random_state()
cb <- oauth_callback_server(path = "/callback", state = st, provider_name = "MockProvider")
cat("  listening on", cb$redirect_uri, "\n")
auth_url <- url_build(modifyList(url_parse(paste0(base, "/authorize")), list(query = list(
  response_type = "code", client_id = "gptr-demo", redirect_uri = cb$redirect_uri, scope = "inference offline_access",
  code_challenge = pk$challenge, code_challenge_method = "S256", state = st))))
cat("  authorize URL:", auth_url, "\n")
invisible(req_perform(request(paste0(base, "/register_challenge?c=", pk$challenge))))
# "browser": a background process follows the redirect twice (wrong state first, then the good one)
browser <- callr::r_bg(function(uri, state) {
  Sys.sleep(0.5)
  r1 <- curl::curl_fetch_memory(paste0(uri, "?code=evil&state=WRONG"))
  r2 <- curl::curl_fetch_memory(paste0(uri, "?code=good-code&state=", state))
  r3 <- curl::curl_fetch_memory(paste0(uri, "?code=replay&state=", state))
  c(r1$status_code, r2$status_code, r3$status_code)
}, args = list(uri = cb$redirect_uri, state = st))
got <- cb$wait(timeout = 10)
for (i in 1:20) { httpuv::service(50); if (!browser$is_alive()) break }
cb$close()
cat("  callback result: code=", got$code, " state ok=", identical(got$state, st), "\n", sep = "")
cat("  browser saw HTTP statuses (wrong state, good, replay):", paste(browser$get_result(), collapse = " "), "\n")
bad <- post(paste0(base, "/token"), list(grant_type = "authorization_code", client_id = "gptr-demo", code = got$code,
  code_verifier = "not-the-verifier", redirect_uri = cb$redirect_uri))
cat("  exchange with wrong verifier -> HTTP", bad$status, bad$body$error, "\n")
tok <- post(paste0(base, "/token"), list(grant_type = "authorization_code", client_id = "gptr-demo", code = got$code,
  code_verifier = pk$verifier, redirect_uri = cb$redirect_uri), as = "json")
cat("  exchange (JSON body, as Anthropic's token endpoint expects) -> HTTP", tok$status, " access=", tok$body$access_token, "\n")

cat("\n== credential store + locked refresh ==\n")
path <- file.path(tempfile("gptr-auth-"), "auth.json")
store <- credential_store(path)
invisible(store$modify("mock", function(cur) to_credential(tok$body)))
invisible(store$modify("openrouter", function(cur) list(type = "api_key", key = "sk-or-demo")))
cat("  file mode:", format(file.info(path)$mode), " entries:", paste(vapply(store$list(), function(x) paste0(x$provider, ":", x$type), ""), collapse = ", "), "\n")
cat("  on disk:\n"); cat(paste0("    ", readLines(path)), sep = "\n")
n_refresh <- 0L
refresh_fn <- function(cur) { n_refresh <<- n_refresh + 1L
  r <- post(paste0(base, "/token"), list(grant_type = "refresh_token", client_id = "gptr-demo", refresh_token = cur$refresh))
  if (!r$ok) stop("refresh failed: ", r$body$error); to_credential(r$body) }
c1 <- oauth_resolve(store, "mock", refresh_fn)
cat("  token still valid -> refresh calls:", n_refresh, " access:", c1$access, "\n")
invisible(store$modify("mock", function(cur) { cur$expires <- round(as.numeric(Sys.time()) * 1000) + 60 * 1000; cur }))   # 1 minute left
c2 <- oauth_resolve(store, "mock", refresh_fn)
c3 <- oauth_resolve(store, "mock", refresh_fn)
cat("  <5 min left -> refresh calls:", n_refresh, " access:", c2$access, " refresh:", c2$refresh, "; second resolve reuses:", c3$access, "\n")
store$delete("mock")
cat("  after logout:", paste(vapply(store$list(), function(x) x$provider, ""), collapse = ", "), "\n")

cat("\n== lock contention: 4 processes x 25 increments ==\n")
cpath <- file.path(dirname(path), "counter.json")
oauth_file <- normalizePath("R/oauth.R")
procs <- lapply(1:4, function(i) callr::r_bg(function(src, cpath) {
  source(src); s <- credential_store(cpath)
  for (k in 1:25) s$modify("counter", function(cur) list(type = "api_key", key = as.character(as.integer((cur$key %||% "0")) + 1L)))
  TRUE
}, args = list(src = oauth_file, cpath = cpath)))
for (p in procs) p$wait(60000)
cat("  final counter:", credential_store(cpath)$read("counter")$key, "(expected 100)\n")

cat("\n== device-code flow against the mock (pending, slow_down, pending, success) ==\n")
dev <- post(paste0(base, "/device/code"), list(client_id = "gptr-demo", scope = "inference"))$body
cat("  user_code:", dev$user_code, " verification_uri:", dev$verification_uri, " interval:", dev$interval, "\n")
sleeps <- numeric()
t0 <- Sys.time()
cred <- oauth_device_poll(interval = dev$interval, expires_in = dev$expires_in, wait_before_first_poll = TRUE,
  sleep = function(s) { sleeps[[length(sleeps) + 1L]] <<- s; Sys.sleep(s / 10) },       # 10x faster than real time
  poll = function() {
    r <- post(paste0(base, "/token"), list(grant_type = "urn:ietf:params:oauth:grant-type:device_code", client_id = "gptr-demo", device_code = dev$device_code))
    if (r$ok) return(list(status = "complete", value = to_credential(r$body)))
    switch(r$body$error %||% "",
      authorization_pending = list(status = "pending"),
      slow_down = list(status = "slow_down", interval = r$body$interval),
      list(status = "failed", message = paste("device flow failed:", r$body$error)))
  })
cat("  sleeps requested (s):", paste(sleeps, collapse = ", "), " -> access:", cred$access, "\n")
```

Observed output:

```
== PKCE against the RFC 7636 appendix B vector ==
  challenge: E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM  matches RFC: TRUE 
  random verifier length: 43  charset ok: TRUE 
== JWT claim extraction (fabricated, unsigned token) ==
  account id: acct_demo_123 
== manual paste parsing ==
  http://localhost:53692/callback?code=abc123&state=xyz   -> code=abc123 state=xyz
  abc123#xyz                                              -> code=abc123 state=xyz
  code=abc123&state=xyz                                   -> code=abc123 state=xyz
  abc123                                                  -> code=abc123 state=NULL
== authorization-code + PKCE with loopback callback ==
  listening on http://127.0.0.1:23366/callback 
  authorize URL: http://127.0.0.1:4438/authorize?response_type=code&client_id=gptr-demo&redirect_uri=http%3A%2F%2F127.0.0.1%3A23366%2Fcallback&scope=inference%20offline_access&code_challenge=AlxQLWCFbbk7MgaZujh1Iw0xuvPufyGsqKtvqdygJLA&code_challenge_method=S256&state=01e436934e3ee2d6d82e7b08a4ef447e 
  callback result: code=good-code state ok=TRUE
  browser saw HTTP statuses (wrong state, good, replay): 400 200 409 
  exchange with wrong verifier -> HTTP 400 invalid_grant 
  exchange (JSON body, as Anthropic's token endpoint expects) -> HTTP 200  access= access-1 
== credential store + locked refresh ==
  file mode: 600  entries: mock:oauth, openrouter:api_key 
  on disk:
    {
      "mock": {
        "type": "oauth",
        "access": "access-1",
        "refresh": "refresh-1",
        "expires": 1790728750270
      },
      "openrouter": {
        "type": "api_key",
        "key": "sk-or-demo"
      }
    }
  token still valid -> refresh calls: 0  access: access-1 
  <5 min left -> refresh calls: 1  access: access-2  refresh: refresh-2 ; second resolve reuses: access-2 
  after logout: openrouter 
== lock contention: 4 processes x 25 increments ==
  final counter: 100 (expected 100)
== device-code flow against the mock (pending, slow_down, pending, success) ==
  user_code: WDJB-MJHT  verification_uri: https://example.com/device  interval: 1 
  sleeps requested (s): 1, 1, 2, 2  -> access: device-access 
```

### 5.7 What was not run

- No request was sent to Anthropic, OpenAI, Google, OpenRouter, TypeSafe or
  any other paid endpoint. Request bodies are structurally checked only.
- No real OAuth login was performed; flows were exercised against a local
  mock.
- `claude -p` and `codex exec` were not run (they would consume plan or API
  usage); only `--version` / `--help` were executed
  (`claude` 2.1.261, `codex-cli` 0.157.0).
- Nothing was tested on Windows or Linux.

---

## 6. CRAN and cross-platform considerations

CRAN policy:

1. **No network in checks.** All normaliser, parser, hand-off and cost tests
   run from fixtures. HTTP tests use a local server and must be skipped on
   CRAN (`testthat::skip_on_cran()`), because opening sockets can fail on check
   machines. Examples that need keys: `@examplesIf
   nzchar(Sys.getenv("ANTHROPIC_API_KEY"))` or `\dontrun{}`.
2. **File writes** only below `tools::R_user_dir("gptr", which)`, the project
   `.gptr/` directory the user initialised, or `tempdir()`. `auth.json` is
   created only by an explicit `auth_login()` call. On this machine
   `R_user_dir("gptr", "config")` is
   `~/Library/Preferences/org.R-project.R/R/gptr` (executed).
3. **No compiled code** is needed for anything in section 5.
4. **ASCII-only sources**: write non-ASCII characters as `\uXXXX` escapes in R
   code; fixtures with UTF-8 bytes go to `tests/testthat/fixtures` or
   `inst/extdata`.
5. **Package size**: the models.dev file is 5.3 MB; ship a trimmed snapshot
   (a handful of providers, only the fields of `gptr_model`) as compressed
   `.rds`.
6. **No global state changes**: do not call `Sys.setenv()` for keys read from
   `.env` unless the user asked (prefer an internal environment); restore
   `options()`; `Sys.umask()` is restored in the prototype with `on.exit`.
7. **User agent**: identify as `gptr/<version> (R <version>; <platform>)`.
8. **Ports**: the loopback server uses a random free port
   (`httpuv::randomPort()`) except for providers that fix the port.

Windows specifics:

1. **Encoding.** R >= 4.2 on Windows uses UTF-8 natively (UCRT); older
   versions use the ANSI code page. The prototypes call `enc2utf8()` before
   `charToRaw()` and set `Encoding(x) <- "UTF-8"` after `rawToChar()`, and
   split SSE on bytes, so they do not depend on the native encoding.
   Recommend `Depends: R (>= 4.2)`. (LIKELY; not run on Windows.)
2. **File permissions.** `Sys.chmod()` / `Sys.umask()` do not provide Unix
   permission semantics on Windows; protection of `auth.json` relies on the
   ACL of the user profile directory. Offer `keyring` (Windows Credential
   Manager) as the recommended store on Windows. (LIKELY.)
3. **Locking.** The prototype lock uses `dir.create()` (atomic on all
   platforms) with a staleness timeout; this avoids a dependency on POSIX
   `flock`. `file.rename()` onto an existing file worked on macOS (executed);
   on Windows it can fail when another process holds the target open, so the
   prototype falls back to `file.copy(overwrite = TRUE)`. (Fallback path
   UNCERTAIN until tested on Windows.)
4. **Loopback server.** Bind to `127.0.0.1`, never `0.0.0.0`, to avoid the
   Windows firewall prompt. (LIKELY.) OpenAI's flow requires the literal host
   `127.0.0.1` in the redirect URI.
5. **Opening the browser.** Use `utils::browseURL(url)`; in RStudio Server,
   Posit Workbench, Jupyter on a remote host or SSH sessions the redirect to
   the loopback address cannot reach the R process, so always print the URL
   and accept a pasted redirect URL, and prefer device-code flows where the
   provider has one.
6. **TLS and proxies.** libcurl on Windows uses Schannel and the system
   certificate store; corporate proxies are honoured through
   `HTTPS_PROXY`/`NO_PROXY`, and `curl::ie_get_proxy_for_url()` can read the
   system proxy. Provide a `gptr.proxy` option that maps to
   `httr2::req_proxy()`.
7. **No shell.** The `!command` key syntax must go through
   `processx::run()` with an explicit argument vector or through
   `system2()`; do not assume `sh`.
8. **CLI bridges.** On Windows, npm-installed command line tools are usually
   `.cmd` shims rather than `.exe` files; resolve the path with `Sys.which()`
   and verify on a Windows machine how `processx` must start them (directly or
   through `cmd.exe /c`). (UNCERTAIN; not tested.)

Interrupts: the polling client sleeps 10 ms when no data is available, which
gives R a chance to deliver the user interrupt; `tryCatch(interrupt = ...)`
turns it into the `aborted` terminal event (REQ-38). With
`blocking = TRUE` the read blocks inside libcurl until data arrives.

---

## 7. Risks, pitfalls, open questions

Risks and pitfalls (all observed or verified unless marked):

1. **`httr2::req_timeout()` sets a total transfer timeout**
   (`timeout_ms`, executed `body(req_timeout)`). A 10-minute generation would
   be cut. For streams set `req_options(connecttimeout = 30, low_speed_time =
   <idle seconds>, low_speed_limit = 1)` and implement the idle timeout in the
   read loop as in 5.4.
2. **jsonlite shape traps**: `list()` -> `[]`, `character(0)` -> `[]`,
   length-1 vectors unboxed with `auto_unbox = TRUE`, `NULL` list elements
   need `null = "null"`, integers above 2^53 become doubles
   (`bigint_as_char = TRUE` helps below 2^64). Tool schemas coming from users
   must be normalised (`properties` named list, `required` unnamed list).
3. **Quadratic string growth**: `paste0(text, delta)` per delta is fine for
   normal outputs (59 KB in 6000 deltas ran at 8,700-13,100 events/s) but tool
   arguments of hundreds of KB must not be re-scanned per delta; the
   incremental parser solves this (0.04-0.06 s to scan 180 KB).
4. **Stealth use of subscription tokens** (Anthropic, Codex backend, Copilot)
   breaks when the vendor changes client versions, headers or policy, and
   violates Anthropic's published terms. Account suspension risk falls on
   gptr's users. Do not ship.
5. **Catalog drift**: model ids, prices and thinking capabilities change
   monthly; most of `generate-models.ts` is hand-written corrections on top of
   models.dev. gptr needs an override file (`.gptr/models.json` or an R list)
   and must tolerate unknown models (let the user pass `api` + `base_url`).
6. **Thinking parameters are model specific**: sending `budget_tokens` to an
   adaptive model or `thinking: disabled` to an always-thinking model returns
   HTTP 400. The catalog must carry `force_adaptive_thinking` and
   `thinking_level_map$off`.
7. **Signatures must round-trip byte-exact** (Anthropic signatures, OpenAI
   encrypted reasoning items, Gemini thought signatures). Storing the session
   as an R script / Rmd (REQ-24) must not lose them: keep a JSON side-car or
   an encoded chunk for assistant messages. Newer Claude models additionally
   bind thinking blocks to the conversation ("preserved thinking"), so editing
   earlier turns of a session document can invalidate stored thinking blocks;
   on a mismatch drop the thinking blocks rather than fail. (LIKELY, from the
   Claude API reference; not tested.)
8. **Chat Completions differences** between vendors are numerous (roles,
   `max_tokens` vs `max_completion_tokens`, usage placement, reasoning field
   names); ship the compat table and allow per-provider overrides.
9. **Gemini API surface may be changing** (see 2.5.5).
10. **Fixed OAuth ports** (1455, 53692) can be occupied, for example by the
    Codex CLI; always support the paste fallback.
11. **Pi's `partial-json` semantics** were first read through a summarising
    fetcher and later checked by the verifier against the raw source (2.8);
    the R implementation follows that behaviour but deliberately keeps `12.`
    as `12` (the JS library drops the key in that case) and does not accept
    `NaN`/`Infinity`.
12. **Locale**: tests ran in the C locale; printing of non-ASCII text is
    escaped there, data are correct.

Open questions:

1. Must an open-source app be registered/approved before
   `dynamic_agent_client` works? Pi issue 10184 shows an `invalid_client`
   failure. (The redirect-path part of this question is resolved: the
   documentation's example is `http://127.0.0.1:1455/auth/callback`, the same
   as Pi, and the path must stay unchanged across sign-ins - see 3.8.)
2. Does the OpenAI program allow unattended use (scripts, `Rscript`, knitr
   rendering)? The "preview limitations" page lists `background` among the
   request fields to omit (verifier, raw text: "Omit `background`,
   `conversation`, ..."), so that entry is about the Responses parameter; no
   statement about unattended scripts was found (still open).
3. Will Anthropic re-introduce a separate programmatic credit for `claude -p`
   (paused since 2026-06-15)? gptr's Claude-plan provider should surface the
   CLI's own error categories (`billing_error`, `rate_limit`, ...).
4. How should gptr expose its R tools to the `claude` / `codex` CLIs - through
   a local MCP server served from the same R session while the CLI runs as a
   sub-process? This needs the event-loop design of the MCP track.
5. Exact TypeSafe Jev API details (rate limits, batch endpoint, error shapes)
   need a live check with a key.
6. Should gptr use `pi.dev`'s processed catalog as an optional source? It
   already contains compat flags and thinking maps, but it is an unpublished
   interface of another project.
7. Windows behaviour of `processx` with npm `.cmd` shims and of
   `file.rename()` under contention.

---

## 8. Sources

Local source (Pi clone, commit `1b347794`):

- `packages/ai/package.json`, `packages/ai/README.md`, `packages/ai/CHANGELOG.md`
- `packages/ai/src/types.ts`, `models.ts`, `model-catalog.ts`,
  `models-store.ts`, `compat.ts`, `env-api-keys.ts`, `oauth.ts`, `index.ts`
- `packages/ai/src/api/anthropic-messages.ts`, `openai-completions.ts`,
  `openai-responses.ts`, `openai-responses-shared.ts`,
  `openai-codex-responses.ts`, `google-generative-ai.ts`, `google-shared.ts`,
  `transform-messages.ts`, `simple-options.ts`, `github-copilot-headers.ts`,
  `constrained-sampling.ts`, `mistral-conversations.ts`, `cloudflare.ts`,
  `system-one-shared.ts`, `typesafe-system-one.ts`,
  `cloudflare-workers-ai-system-one.ts`, `pi-messages.ts`
- `packages/ai/src/auth/types.ts`, `resolve.ts`, `helpers.ts`, `context.ts`,
  `credential-store.ts`, `oauth/anthropic.ts`, `oauth/openai-codex.ts`,
  `oauth/openai-chatgpt.ts`, `oauth/github-copilot.ts`, `oauth/openrouter.ts`,
  `oauth/xai.ts`, `oauth/kimi-coding.ts`, `oauth/meta.ts`, `oauth/radius.ts`,
  `oauth/callback-server.ts`, `oauth/device-code.ts`, `oauth/pkce.ts`,
  `oauth/load.ts`
- `packages/ai/src/providers/*.ts`
- `packages/ai/src/utils/event-stream.ts`, `json-parse.ts`,
  `provider-retry.ts`, `retry.ts`, `overflow.ts`, `estimate.ts`,
  `error-body.ts`, `transcript.ts`, `text.ts`, `hash.ts`,
  `sanitize-unicode.ts`, `pi-user-agent.ts`
- `packages/ai/scripts/generate-models.ts`, `model-data.ts`,
  `models-dev-reasoning-options.ts`
- `packages/ai/test/anthropic-sse-parsing.test.ts`,
  `openai-codex-stream.test.ts`, `openai-responses-terminal-event.test.ts`
- `packages/coding-agent/src/core/auth-storage.ts`,
  `remote-catalog-provider.ts`, `provider-attribution.ts`,
  `auth-guidance.ts`, `modes/interactive/interactive-mode.ts`
- `packages/coding-agent/docs/providers.md`, `models.md`,
  `custom-provider.md`, `environment-variables.md`, `settings.md`
- Claude API reference bundled with Claude Code 2.1.284 (skill `claude-api`):
  `curl/examples.md`, `shared/tool-use-concepts.md`,
  `shared/anthropic-cli.md`, `typescript/claude-api/streaming.md`

Web (all fetched 2026-09-29):

- https://models.dev/api.json and https://models.dev/models.json?type=decision
- https://pi.dev/api/models/providers/anthropic?types=chat,image,classifier
  (and the same path for the other 41 provider ids)
- https://code.claude.com/docs/en/legal-and-compliance
- https://code.claude.com/docs/en/headless
- https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan
- https://developers.openai.com/siwc/website
- https://developers.openai.com/siwc/quickstart
- https://developers.openai.com/siwc/token-sharing-open-source
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/token-reference
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server
- https://learn.chatgpt.com/docs/auth
- https://learn.chatgpt.com/docs/non-interactive-mode
- https://learn.chatgpt.com/docs/whats-new/september-28-october-2-2026
- https://ai.google.dev/api/generate-content
- https://ai.google.dev/gemini-api/docs/thinking
- https://raw.githubusercontent.com/promplate/partial-json-parser-js/main/src/index.ts
- https://github.com/earendil-works/pi/issues/10184
- https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access/
- https://venturebeat.com/technology/anthropic-reinstates-openclaw-and-third-party-agent-usage-on-claude-subscriptions-with-a-catch
- https://www.digitalapplied.com/blog/anthropic-claude-credit-overhaul-june-15-2026

Executed commands (all with `Rscript --vanilla` in the scratch work
directory): `test_partial_json.R`, `test_normalize.R`, `test_http_stream.R`,
`test_slow_stream.R`, `test_messages.R`, `test_oauth.R`, `provider_table.R`,
`fetch_pi_catalog.R`; plus `claude --version`, `claude --help`,
`codex --version`.

---

## Verification log

Adversarial fact-check, 2026-09-29, against the Pi clone at commit
`1b347794e2a630e4359f2584f4eea388145d0ddf` (re-confirmed with `git log`),
raw (not summarised) re-fetches of the vendor pages, the live `pi.dev` and
`models.dev` catalogs, the Claude API reference bundled with Claude Code
2.1.284, and `Rscript --vanilla` runs (R 4.4.3, httr2 1.2.2, curl 7.0.0,
jsonlite 2.0.0). Scratch files:
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/verify-03/v2` and `v3`.
No paid API was called and no credential file was read.

| # | Claim | Verdict | Source used |
|---|---|---|---|
| 1 | 42 built-in providers; 10 `KnownApi` chat wire formats; 26 providers use `openai-completions` | confirmed | `providers/all.ts` `builtinProviders()` (42 entries), `types.ts:17-27`, section 2.4 table count |
| 2 | Event protocol: 12 event types, `done` reasons `stop/length/toolUse/deferred`, `error` reasons `error/aborted` | confirmed (added the `streamSimple()` auth-throw exception) | `types.ts:751-783` |
| 3 | `parseStreamingJson()` chain strict -> repair -> `partial-json` -> `{}`; `Allow.ALL` semantics | confirmed; `Allow.ALL` upgraded LIKELY -> VERIFIED | `utils/json-parse.ts:1,104-124`; raw `partial-json-parser-js` `src/index.ts` (default `allowPartial = Allow.ALL`) |
| 4 | Default thinking budgets 1024/2048/8192/16384, min answer tokens 1024, context margin 4096 | confirmed; Anthropic budget formula amended (context clamp) | `api/simple-options.ts:12,52-92`, `anthropic-messages.ts:895-911` |
| 5 | `calculateCost()` tiers and "1h cache writes cost 2x base input" | confirmed | `models.ts:1193-1213`; prototype cost 0.0219 recomputed by hand |
| 6 | Tool-id rules (Anthropic 64, chat completions 40 + 8-char hash, Mistral 9, Responses min `max_output_tokens` 16, prompt cache key 64) | confirmed | `anthropic-messages.ts:1215-1218`, `openai-completions.ts:1194-1218`, `mistral-conversations.ts:28`, `openai-responses.ts:33`, `openai-prompt-cache.ts:1` |
| 7 | Anthropic stealth-mode constants (`claude-cli/2.1.280`, `x-app: cli`, betas `claude-code-20250219`,`oauth-2025-04-20`, Claude Code system block, tool list) and the beta-header list | confirmed | `anthropic-messages.ts:86-123,181-186,915,949-968,1000-1041,1085-1100` |
| 8 | OAuth constants (Anthropic, OpenAI ChatGPT, Codex, Copilot, OpenRouter, xAI, Kimi, Meta, Radius), base64 client ids decode to the stated values | confirmed | `auth/oauth/*.ts`; `base64 -d` of both encoded ids |
| 9 | OAuth refresh window 5 min / 15 s; auth.json 0600/0700, sync lock 10 x 20 ms, async backoff to 30 s, stale 30 s | confirmed | `auth/resolve.ts:102-103`, `coding-agent/src/core/auth-storage.ts:25,59,69-160` |
| 10 | Remote catalog URL, 4 h interval, 4 s timeout, 304/404/501 handling | confirmed | `coding-agent/src/core/remote-catalog-provider.ts:13-15,102-145` |
| 11 | Provider retry policy (408/409/429/>=500, `x-should-retry`, `min(0.5*2^n, 8)` s, 60 s cap, default 0 retries) | confirmed | `utils/provider-retry.ts:1-125` |
| 12 | Live catalog facts (Anthropic 16 models, OpenAI 44, Google 22, Groq 7, OpenRouter 462 split 383/15/57/7, Radius 28 at `https://radius.pi.dev/v1`; Opus 5.5 and GPT-5.5 entries) | confirmed; `supportsTemperature:false` list corrected ("Opus 4.7+" was incomplete: Sonnet 5.5 also has it) | `https://pi.dev/api/models/providers/{id}?types=chat,image,classifier` re-fetched |
| 13 | models.dev: 225 providers, 8,323 models, npm distribution 184/8/6/2/2 | confirmed (size now 5,263,829 bytes, 7,276 tool-capable - normal drift) | `https://models.dev/api.json` re-fetched |
| 14 | Anthropic legal-and-compliance quotes | confirmed character exact; recommendation softened: the "running Claude Code in your products" clause (Commercial Terms) was omitted and is now quoted, applicability to gptr marked UNCERTAIN | raw HTML of https://code.claude.com/docs/en/legal-and-compliance |
| 15 | Help-centre statement that the programmatic credit was paused on 2026-06-15 | confirmed | raw HTML of the support.claude.com article (dated June 16, 2026) |
| 16 | OpenAI SIWC: endpoints, scopes, `dynamic_agent_client`, token response incl. `earliest_refresh_at`, 1 h / 30 d rotating lifetimes, error codes, 0600 storage | confirmed | raw HTML of the six `developers.openai.com/siwc/token-sharing-open-source*` pages |
| 17 | SIWC redirect path "documentation example is `/callback`" | corrected: the docs example is `http://127.0.0.1:1455/auth/callback`; path must not change; Pi matches | `/sign-in` page, raw text |
| 18 | SIWC unsupported features list | corrected to the verbatim field list (adds `max_output_tokens`, `metadata`, `prompt_cache_retention`, `top_p`, `previous_response_id`, `system` items, ...) | `/preview-limitations` page, raw text |
| 19 | Pi issue 10184 (`invalid_client`, closed not planned) | confirmed | GitHub REST API |
| 20 | `codex exec --json` event types | corrected (added `turn.failed`) | https://learn.chatgpt.com/docs/non-interactive-mode |
| 21 | `claude --bare` never reads OAuth credentials; stream-json `stream_event` + `.event.delta.type` jq filter | confirmed | https://code.claude.com/docs/en/headless; `claude --help`; `claude` 2.1.261, `codex-cli` 0.157.0 |
| 22 | Anthropic API cross-check (effort values, `budget_tokens` 400 on Opus 4.7+/Sonnet 5+/Fable 5, `disabled` 400 on Opus 5.5/Sonnet 5.5/Fable, Opus 5.5 default effort `medium`, display default `omitted`, `INVALID_JSON` guidance, `anthropic-version: 2023-06-01`) | confirmed | bundled `claude-api` skill SKILL.md, `shared/tool-use-concepts.md:72-81`, `curl/examples.md:19` |
| 23 | Gemini `:streamGenerateContent?alt=sse`, `x-goog-api-key`, usage field names; "newer Interactions API" UNCERTAIN note | confirmed; note updated (the `/v1beta/interactions` endpoint is documented) | https://ai.google.dev/api/generate-content, https://ai.google.dev/gemini-api/docs/api-key |
| 24 | `httr2::req_timeout()` is a total timeout | confirmed (`timeout_ms = seconds*1000, connecttimeout = 0`) | `body(httr2::req_timeout)` executed |
| 25 | httr2 `(>= 1.1.0)` with `mock` on `req_perform_connection`; curl `(>= 6.0.0)` | corrected to httr2 `>= 1.2.0` (recommend 1.2.2) and curl `>= 6.4.0` | httr2 NEWS.md (mocking #651 in 1.2.0, fix #817 in 1.2.2); `packageDescription("httr2")$Imports` |
| 26 | jsonlite traps (`list()` -> `[]`, named empty list -> `{}`, unboxing, 2^53) and the recommended `digits = NA` | confirmed; caveat added (`digits = NA` keeps only 15 significant digits) | executed `toJSON`/`parse_json` checks |
| 27 | `readRenviron()` and a leading `export` | confirmed and made precise (creates a variable named `export D`) | executed |
| 28 | ellmer 0.4.0 imports httr2 (>= 1.2.1), jsonlite, later, promises, coro, S7 | confirmed | `packageDescription("ellmer")` |
| 29 | All section 5 prototypes run and reproduce the shown output | corrected: `test_slow_stream.R` and `test_oauth.R` had start-up races (failed 3/6 and 2/6 under load) - fixed in place, now 6/6 and 8/8; two missing fixtures added to 5.3; other scripts reproduce exactly apart from timings | re-extracted every code block from this report and ran it |
| 30 | Partial-JSON speed-up "13-17x" | corrected to about 13-18x (the author's own numbers give 12.8x and 18.1x; verifier run 14.2x) | `test_partial_json.R` re-run |
| 31 | Throughput 8,700-13,100 events/s | confirmed order of magnitude (verifier run 13,771 events/s) | `test_normalize.R` re-run |
| 32 | Press-coverage dates (The Register, VentureBeat), Windows behaviour, TypeSafe live API, whether gptr's `claude -p` bridge counts as "running Claude Code in your products" | unverifiable here (left as LIKELY / UNCERTAIN) | - |

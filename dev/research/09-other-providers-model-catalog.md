# Track 09 — Gemini, OpenAI-compatible providers, local models, Azure, Bedrock, Copilot, model catalog

Date: 2026-09-29. Machine: macOS, R 4.4.3 (`Rscript --vanilla`, locale **C**), httr2 1.2.2, curl 7.0.0 (libcurl 8.14.1),
openssl 2.3.5 (OpenSSL 3.5.4), digest 0.6.39, jsonlite 2.0.0, httpuv 1.6.17. Pi reference clone at commit `1b347794`
(abbreviated below as `PI/` = `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi/packages/`).
Scratch work (prototypes, fetched docs, snapshots): `SCR/` = `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-09/`
(new, verified code is in `SCR/v2/`; web copies fetched today are in `SCR/web/`).

Evidence tags: **VERIFIED** = I saw the source/doc text or ran the code myself; **LIKELY** = strong indirect evidence;
**UNCERTAIN** = not confirmed. No paid LLM API calls were made; all network experiments used free catalog endpoints
(models.dev) or local mock servers.

Relation to other reports: `03-pi-ai-providers-auth.md` already documents Pi's unified types, the Anthropic/OpenAI/Responses
adapters, cost/thinking helpers and OAuth. This report is self-contained for its scope (Gemini, the OpenAI-compatible
universe, local servers, Azure, Bedrock, Copilot, the model catalog and model naming), and it corrects/extends 03 on
one point: **httr2's `resp_stream_sse()` on a blocking connection delays events** (section 2.10).

A previous researcher left unverified drafts in `SCR/` (`oai_stream.R`, `mock_server.R`, `run_stream_demo.R`,
models.dev analysis scripts). I re-ran them: the old demo produced mojibake (non-ASCII literals parsed in a C locale),
the curl transport crashed (`No URL set`), and its "streamed incrementally" check was FALSE. All prototypes below were
rewritten in `SCR/v2/` and re-verified; the models.dev analysis scripts were re-run on a fresh download.

---

## 1. Executive summary

1. **Gemini (generateContent) wire format** (VERIFIED, ai.google.dev docs fetched today + Pi `google-shared.ts`):
   `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse`,
   header `x-goog-api-key: <key>` (the guides use this header; the API-reference curl samples use a `?key=` query parameter
   instead; both are accepted, gptr should use the header so keys never appear in URLs/logs); body `{systemInstruction, contents[{role:"user"|"model", parts[]}], tools[{functionDeclarations[]}], toolConfig{functionCallingConfig{mode}}, generationConfig{maxOutputTokens, temperature, thinkingConfig{includeThoughts, thinkingLevel|thinkingBudget}}}`.
   Each SSE `data:` line is a complete `GenerateContentResponse`; **there is no `[DONE]` sentinel** (stream ends at EOF);
   `functionCall` parts arrive whole (no argument deltas).
2. **Thought signatures are mandatory for Gemini 3 function calling**: echo every `thoughtSignature` back on the exact part
   it came on; missing it on the first `functionCall` of each step of the current turn yields HTTP 400. Parallel calls carry
   the signature only on the first call. Signatures are only valid for the same provider+model (Pi drops them otherwise).
3. **Gemini thinking controls differ per model**: Gemini 3.x uses `thinkingLevel` (`MINIMAL|LOW|MEDIUM|HIGH`; `minimal` is an
   *error* on 3.8/3.7 Flash; 3.1 Pro cannot disable thinking); Gemini 2.5 uses `thinkingBudget` (`-1` dynamic, `0` off,
   ranges per model). Drive this from models.dev `reasoning_options`, as Pi does.
4. **Current Gemini IDs** (VERIFIED live): stable `gemini-3.8-flash` (docs' default and recommended), `gemini-3.7-flash`,
   `gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite`, `gemini-3.1-flash-lite`; preview `gemini-3.1-pro-preview`,
   `gemini-3-flash-preview`; aliases `gemini-flash-latest`, `gemini-flash-lite-latest`. `generateContent` is now officially
   "legacy but fully supported"; the **Interactions API** (`POST /v1beta/interactions`, GA June 2026, stores state server-side
   by default) is where new features launch. Build `generateContent` first; keep the adapter boundary so Interactions can be added.
5. **The OpenAI-compatible universe is one wire format plus ~27 compat flags.** Pi's `OpenAICompletionsCompat`
   (`PI/ai/src/types.ts:789-866`) plus URL/provider auto-detection (`PI/ai/src/api/openai-completions.ts:1585-1726`) is the
   reference. Every flag, default and effect is tabulated in 3.3. gptr should port this as an R list of flags, resolved as
   `detected defaults <- catalog compat <- user config`.
6. **Reasoning text arrives under three different field names**: `reasoning_content` (DeepSeek, llama.cpp), `reasoning`
   (OpenRouter, Groq, Cerebras, vLLM ≥ rename, Ollama, Together), `reasoning_text`. Rule (Pi): take the *first non-empty*
   of `reasoning_content`, `reasoning`, `reasoning_text` per delta, and remember which field it was. Replay it in the same field.
   Some models (Together DeepSeek-R1, Groq `reasoning_format=raw`, llama.cpp `--reasoning-format none`) put `<think>` tags
   inside `content` instead.
7. **Replay rules that break naive clients**: DeepSeek returns 400 if `reasoning_content` is not sent back when tools are
   used; Cerebras wants `reasoning` echoed; OpenRouter wants `reasoning_details` echoed unmodified; Mistral requires
   9-character alphanumeric tool-call IDs; Groq returns 400 for `messages[].name`, `logprobs`, `logit_bias`; Ollama rejects
   image URLs (base64 only) and ignores `tool_choice`; OpenRouter sends `: OPENROUTER PROCESSING` comment lines and
   mid-stream errors as a chunk with `finish_reason:"error"` and an `error` object.
8. **Local servers** (VERIFIED docs): Ollama `http://localhost:11434/v1` (dummy key), LM Studio `http://localhost:1234/v1`,
   llama.cpp `http://127.0.0.1:8080/v1` (tools need `--jinja`, reasoning in `reasoning_content`, key via `--api-key`),
   vLLM `http://localhost:8000/v1` (reasoning renamed to `reasoning`; tools need `--enable-auto-tool-choice --tool-call-parser`).
   Pi's llama.cpp compat profile is a good default for all local servers:
   `{store:F, developer:F, reasoning_effort:F, max_tokens field, strict:F}`.
9. **Azure OpenAI v1** (VERIFIED MS Learn): base `https://{resource}.openai.azure.com/openai/v1/` (also `*.services.ai.azure.com`),
   no `api-version` needed, `api-key: <key>` header (or `Authorization: Bearer <Entra token>`), `model` = *deployment name*.
   It speaks both Responses and Chat Completions. Pi env vars: `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_BASE_URL` |
   `AZURE_OPENAI_RESOURCE_NAME`, `AZURE_OPENAI_DEPLOYMENT_NAME_MAP`, `AZURE_OPENAI_API_VERSION` (default `"v1"`).
10. **Bedrock is cheaper than feared.** Bedrock now has (a) API keys (`AWS_BEARER_TOKEN_BEDROCK`, sent as `Authorization: Bearer`)
    and (b) an OpenAI-compatible endpoint `https://bedrock-runtime.{region}.amazonaws.com/openai/v1/chat/completions`
    (VERIFIED AWS docs). So Bedrock can ship in phase 1 as just another OpenAI-compatible provider with **no SigV4 and no
    eventstream**. Full Converse support needs SigV4 + the binary `application/vnd.amazon.eventstream` framing; both are
    **implemented and verified in pure R** here (openssl only): my SigV4 matches both AWS test-suite vectors and libcurl's own
    `CURLOPT_AWS_SIGV4` byte-for-byte, including model IDs containing `:`. The eventstream decoder verifies both CRC32s.
    Recommendation: Bedrock in Imports-only code (openssl is already needed); no AWS SDK.
11. **GitHub Copilot**: GitHub device-code OAuth with an editor client ID, then a token exchange at
    `https://api.{domain}/copilot_internal/v2/token`, base URL from the token's `proxy-ep`, spoofed editor headers.
    Terms-of-service risk: **defer** (Suggests/extension only).
12. **Model catalog**: Pi generates its catalog at build time from `https://models.dev/api.json` (+ OpenRouter, Vercel,
    NVIDIA lists) and overlays `https://pi.dev/api/models/providers/<id>` at run time (4 h interval). models.dev is MIT-licensed.
    Its api.json today: 225 providers, 8,323 models, 5.26 MB (513 KB gzip), strong ETag support (`304` verified).
    Full field schema with counts and types is in 3.8.
13. **CRAN strategy (measured)**: ship a pruned snapshot in `inst/extdata/models-dev.json.gz` (25 providers, 1,227 tool-capable
    non-deprecated models = **51 KB gz / 34 KB xz**, loads in 0.05 s). Refresh only via an explicit `gptr_models_update()`
    into `tools::R_user_dir("gptr","cache")` with `If-None-Match`. Layer order: snapshot < cache < user config < live
    discovery (local servers' `/v1/models`).
14. **Model reference syntax** (prototype verified on the real catalog): `"provider/model-id[:thinking]"`, bare id, alias
    (`sonnet`, `opus`, `haiku`, `gemini`, `flash`, `gpt`, `jev`), family (`claude-sonnet`), with Pi's *last-colon* thinking-suffix
    rule (`:off|minimal|low|medium|high|xhigh|max`). Ambiguous bare IDs are resolved by **models.dev `canonical_model_id` owner**
    (so `gpt-6-sol` goes to `openai`, not azure/copilot) and then by which providers have credentials. IDs are also compared with
    `.`/`-` normalised (`claude-sonnet-5-5` matches OpenRouter's `anthropic/claude-sonnet-5.5`).
    [Verifier correction: the tie-break order is the reverse of the sentence above. The prototype's `break_tie()` (5.5) and
    4.9 first prefer the single *authenticated* provider, and only then the `canonical_model_id` owner; re-run confirmed
    `claude-opus-5-5` with `authenticated = "azure"` resolves to `azure/claude-opus-5-5`.]
15. **NSE for bare names works but is lossy in edge cases** (VERIFIED): `anthropic/claude-sonnet-5-5` deparses to
    `anthropic/claude - sonnet - 5 - 5` (whitespace-stripping recovers it), but `gpt-5.10` becomes `gpt-5.1`, `1e3` becomes `1000`,
    and `gpt-oss-120b` or `gemma4:31b` are *parse errors*. Accept bare symbols and simple calls, always write the resolved,
    quoted canonical ID into the session script, and print the resolution when a bare call contains a decimal number.
16. **Streaming transport finding (VERIFIED, new)**: `httr2::req_perform_connection(blocking = TRUE)` + `resp_stream_sse()`
    (what ellmer 0.4.0 does for sync streaming) batches small events, because each read blocks until 1024 bytes arrive.
    With a server emitting one event every 250 ms the median gap was 0.00 s and the max gap 1.53 s (burst delivery).
    Both `curl::multi_*` with a data callback and `httr2` with `blocking = FALSE` + `resp_stream_raw()` polling delivered
    every event at ~0.25 s spacing. **Use curl multi (or httr2 non-blocking) for all streaming in gptr.**
17. The generic OpenAI-compatible + Gemini streaming client in 5.1 runs unchanged in a **C locale** (UTF-8 split across TCP
    chunks, CRLF/LF mixing, SSE comments, missing `[DONE]`, mid-stream errors, HTTP 401/400) with identical results on both
    transports. It is the reference implementation to port into `R/`.

---

## 2. Findings

### 2.1 Google Gemini API (generateContent) — wire level

Sources (fetched 2026-09-29, copies in `SCR/web/`): API reference `https://ai.google.dev/api/generate-content`
(`api_generate-content.md`), `https://ai.google.dev/api/caching` (ToolConfig, `api_caching.md`), guides under
`https://ai.google.dev/gemini-api/docs/generate-content/*` (text-generation, thinking, thought-signatures, function-calling),
`https://ai.google.dev/gemini-api/docs/models`, `/api-key`, `/openai`, `/interactions-overview`, `/migrate-to-interactions`.
Live re-checks today: the models page and the thinking page (both VERIFIED unchanged).

**Endpoints (VERIFIED)**
- Non-streaming: `POST https://generativelanguage.googleapis.com/v1beta/{model=models/*}:generateContent`.
- Streaming: `POST .../v1beta/models/{model}:streamGenerateContent?alt=sse` (the REST examples use `?alt=sse`;
  ellmer 0.4.0 does the same: `req_url_query(req, alt = "sse")`, executed
  `S7::method(chat_request, ProviderGoogleGemini)`). Without `alt=sse` the stream is a JSON array (not used).
- Model listing: `GET .../v1beta/models` (documented in `api_models.md`).

**Auth (VERIFIED, corrected by verifier)**: header `x-goog-api-key: <key>` in the REST examples of the *guides* (text-generation,
thinking, function-calling, api-key, interactions pages). The *API reference* pages (`/api/generate-content`, `/api/models`,
`/api/caching`) instead use a query parameter, e.g. `...:streamGenerateContent?alt=sse&key=$GEMINI_API_KEY` (live `.md.txt`
copy fetched 2026-09-29 has 23 `key=` samples and 0 `x-goog-api-key`). Both are accepted; gptr should send the header (keeps
the key out of URLs, logs and error messages). The official SDKs read `GEMINI_API_KEY` or
`GOOGLE_API_KEY`; "If both are set, `GOOGLE_API_KEY` takes precedence" (api-key page). Pi reads only `GEMINI_API_KEY`
(`PI/ai/src/providers/google.ts`); models.dev lists `GOOGLE_API_KEY, GOOGLE_GENERATIVE_AI_API_KEY, GEMINI_API_KEY`.
New since 2026-05-28: AI Studio creates *authorization keys* bound to a service account; **unrestricted standard keys are
rejected** (standard keys *with* explicit restrictions continue to work; dormant unrestricted keys are blocked from 2026-05-07).
This is transparent to clients but explains some 401/403s users will report.

**Request body (VERIFIED, API reference "Request body")**: `contents[]` (required), `tools[]`, `toolConfig`,
`safetySettings[]`, `labels`, `systemInstruction` (Content, text only), `generationConfig`, `cachedContent`,
`serviceTier`, `store`.
- `Content = {role: "user"|"model", parts: Part[]}`.
- `Part` has flags `thought` (bool), `thoughtSignature` (base64 string), and exactly one of `text`, `inlineData{mimeType,data,displayName}`,
  `functionCall{id,name,args}`, `functionResponse{id,name,response,parts[],willContinue,scheduling}`, `fileData`,
  `executableCode`, `codeExecutionResult`, `toolCall`, `toolResponse`.
- `FunctionDeclaration = {name, description, behavior, parameters (OpenAPI 3.0 subset) | parametersJsonSchema (full JSON Schema), response | responseJsonSchema}`.
  Name: `a-zA-Z0-9_:.-`, max 128. Pi sends `parametersJsonSchema` (`google-shared.ts:380-401`), which accepts `anyOf`,
  `const` etc. It uses `parameters` only for Cloud Code Assist, where it strips `$schema`, `$id`, `$defs` etc. (`:345-370`).
- `toolConfig.functionCallingConfig = {mode: AUTO|ANY|NONE|VALIDATED, allowedFunctionNames[]}`. `VALIDATED` = constrained decoding,
  default when built-in tools/structured output are combined. Pi picks `VALIDATED` when any tool is strict on Gemini 3+
  (`google-shared.ts:404-436`).
- `generationConfig` fields: `stopSequences` (≤5), `responseMimeType`, `responseSchema`, `responseJsonSchema`,
  `responseModalities`, `candidateCount`, `maxOutputTokens`, `temperature`, `topP`, `topK`, `seed`, `presencePenalty`,
  `frequencyPenalty`, `responseLogprobs`, `logprobs` (0-20), `thinkingConfig`, `imageConfig`, `mediaResolution`, ...
- `thinkingConfig = {includeThoughts: bool, thinkingBudget: int, thinkingLevel: THINKING_LEVEL_UNSPECIFIED|MINIMAL|LOW|MEDIUM|HIGH}`,
  placed **inside `generationConfig`** in REST (the SDKs flatten it into `config`). The reference says `thinkingLevel` is
  "Recommended for Gemini 3 or later models. Use with earlier models results in an error", so never send it to 2.5 models.

**Response (VERIFIED)**: `GenerateContentResponse = {candidates[], promptFeedback{blockReason,safetyRatings}, usageMetadata, modelVersion, responseId, modelStatus}`;
`Candidate = {content, finishReason, safetyRatings, citationMetadata, tokenCount, groundingMetadata, avgLogprobs, logprobsResult, urlContextMetadata, index, finishMessage}`.
In streaming, every SSE event carries one such object with *incremental* parts. `usageMetadata` appears on the final chunk(s).

**UsageMetadata (VERIFIED)**: `promptTokenCount` (includes cached content), `cachedContentTokenCount`, `candidatesTokenCount`,
`toolUsePromptTokenCount`, `thoughtsTokenCount`, `totalTokenCount`, `*TokensDetails[]` per modality, `serviceTier`.
Pi's normalisation (`google-generative-ai.ts:232-251`): `input = promptTokenCount - cachedContentTokenCount`,
`output = candidatesTokenCount + thoughtsTokenCount`, `cacheRead = cachedContentTokenCount`, `cacheWrite = 0`,
`reasoning = thoughtsTokenCount`. Thinking tokens are billed as output (thinking page, "Pricing").

**FinishReason enum (VERIFIED)**: `FINISH_REASON_UNSPECIFIED, STOP, MAX_TOKENS, SAFETY, RECITATION, LANGUAGE, OTHER, BLOCKLIST,
PROHIBITED_CONTENT, SPII, MALFORMED_FUNCTION_CALL, IMAGE_SAFETY, IMAGE_PROHIBITED_CONTENT, IMAGE_OTHER, NO_IMAGE,
IMAGE_RECITATION, UNEXPECTED_TOOL_CALL, TOO_MANY_TOOL_CALLS, MISSING_THOUGHT_SIGNATURE, MALFORMED_RESPONSE, ESCALATION,
PUP_LIMITED_DISABLED`. Pi maps `STOP` to stop (or toolUse if a functionCall was emitted), `MAX_TOKENS` to length, and
everything else to error (`google-shared.ts:441-483`). The last four values are newer than Pi's SDK enum, so gptr must
**default unknown values to `error`** (plus a `finishMessage` passthrough). Missing finish reason at EOF → error
("Google stream ended without a finish reason", `google-generative-ai.ts:276-278`).

**Thinking (VERIFIED live today)**: thinkingLevel support table (thinking guide):

| Level | 3.8/3.7 Flash | 3.6/3.5 Flash | 3.1 Pro | 3.5/3.1 Flash-Lite | 3.1 Flash-Lite Image | 3 Flash | Robotics ER 2 |
|---|---|---|---|---|---|---|---|
| minimal | error | yes | no | yes (default) | yes (default) | yes | yes |
| low | yes | yes | yes | yes | no | yes | yes |
| medium | yes (default) | yes (default) | yes | yes | no | yes | yes |
| high | yes (dynamic) | yes (dynamic) | default, dynamic | dynamic | dynamic | default, dynamic | default, dynamic |

"You cannot disable thinking for Gemini 3.1 Pro. Gemini 3 Flash and Flash-Lite also do not support full thinking-off."
Budgets (2.5): Pro 128-32768 (cannot disable, default dynamic), Flash 0-24576, Flash-Lite 512-24576 (default off); `-1` dynamic, `0` off.
`maxOutputTokens` includes thinking tokens, and hitting it mid-thought returns `MAX_TOKENS` with empty output.
models.dev encodes exactly these capabilities: `gemini-3.8-flash` → `effort[low|medium|high]`,
`gemini-3.5-flash` → `effort[minimal|low|medium|high]`, `gemini-2.5-flash` → `toggle;budget[0-24576]`,
`gemini-2.5-pro` → `budget[128-32768]` (executed `analyze3.R`, output in 5.6).

Pi's Gemini thinking logic (VERIFIED `google-generative-ai.ts:305-471`, `google-shared.ts:47-111`):
- `usesGoogleThinkingLevel(model)` matches `/gemini-3(?:\.\d+)?-(?:pro|flash)/`, `gemini-flash-latest`, `gemini-flash-lite-latest`, `/gemma-?4/`.
- Level path: clamp the Pi level via `thinkingLevelMap` (from models.dev effort values), then send `thinkingLevel` in upper case.
- Budget path (2.5): per-model budgets, with custom `thinkingBudgets` overriding:
  `2.5-pro {minimal:128, low:2048, medium:8192, high:32768}`; `2.5-flash-lite {512, 2048, 8192, 24576}`;
  `2.5-flash {128, 2048, 8192, 24576}`; otherwise `-1`.
- Off: `thinkingBudget: 0` for budget models; for level models the lowest supported level (`getDisabledGoogleThinkingConfig`).
- `includeThoughts: true` whenever thinking is enabled, so thought summaries stream as `thought: true` parts.

**Thought signatures (VERIFIED thought-signatures guide + Pi)**:
- "When using Gemini 3 models, you must pass back thought signatures during function calling, otherwise you will get a
  validation error (4xx status code)." This includes `minimal` level.
- Single call: the `functionCall` part carries `thoughtSignature`. Parallel calls: **only the first** `functionCall` part
  carries it. Sequential steps: each step's first call carries one, and *all* must be returned. Validation covers the
  *current turn* only: everything after the most recent user message containing standard content (not a `functionResponse`).
- Error text form: "Function call `FC1` in the `1.` content block is missing a `thought_signature`."
- Non-functionCall responses may carry a signature on the **last part**. Returning it is recommended but not validated.
- "Don't concatenate parts with signatures together. Don't merge one part with a signature with another part without a
  signature." Pi keeps the signature on the block it arrived on, retaining the last non-empty one within a streamed block
  (`retainThoughtSignature`, `google-shared.ts:141-144`). It validates base64 (`/^[A-Za-z0-9+/]+={0,2}$/`, length%4==0)
  and replays only for the same provider+model (`:146-160`). Empty text/thinking blocks are kept *if* they carry a signature
  (`:236-257`), because dropping them causes "thought-only STOP" failures.
- Cross-model hand-off: thinking from another model is replayed as plain text (no `thought` flag, no signature, `:258-264`).
- The doc JSON uses both `thoughtSignature` and `thought_signature` spellings. The API reference field is `thoughtSignature`
  (protobuf JSON accepts both) — LIKELY; emit `thoughtSignature`.

**Function calls/responses (VERIFIED)**: `functionCall.id` is optional; Gemini 3 returns IDs, and Pi requires them for
Gemini ≥ 3, `claude-*` and `gpt-oss-*` behind Google APIs (`requiresToolCallId`, `google-shared.ts:165-178`), normalising
to `[A-Za-z0-9_-]{1,64}`. When an ID is absent or duplicated, Pi generates `<name>_<ms>_<n>` (`google-generative-ai.ts:195-201`).
Tool results are sent as `{role:"user", parts:[{functionResponse:{name, id?, response:{output: text} | {error: text}}}]}`;
consecutive results are merged into one user turn (`google-shared.ts:284-331`).
**Multimodal function responses** (Gemini 3 only): images/PDF as `functionResponse.parts[].inlineData`
(`image/png|jpeg|webp`, `application/pdf`, `text/plain`), optionally referenced from `response` via `{"$ref": "<displayName>"}`.
For Gemini < 3, Pi appends a separate user turn `[{text:"Tool result image:"}, inlineData...]` (`:295-338`).
Streaming: "With generateContent, streaming function calls arrived complete in a single chunk" (migration guide), so the
Gemini adapter emits toolcall start/delta/end at once (`google-generative-ai.ts:175-220`).

**Inline images (VERIFIED)**: `{"inlineData": {"mimeType": "image/png", "data": "<base64>"}}` inside `parts`.
Supported image MIME types: png, jpeg, jpg, webp, heic, heif, gif, avif (Blob reference). Pi converts user image blocks
directly (`google-shared.ts:210-221`).

**Errors (VERIFIED/LIKELY)**: error bodies are Google-style `{"error": {"code": 400, "message": "...", "status": "INVALID_ARGUMENT"}}`
(ellmer extracts `json$error$message`, VERIFIED by printing its `base_request` method). Spend-based limits return
`429 RESOURCE_EXHAUSTED` (rate-limits page). Limits are per project, not per key.

**OpenAI-compatible Gemini endpoint (VERIFIED `/openai` page)**: `https://generativelanguage.googleapis.com/v1beta/openai/`
with `Authorization: Bearer <GEMINI key>`. `reasoning_effort` maps to thinking level/budget
(minimal→low on 3.1 Pro; 2.5 budgets 1,024/1,024/8,192/24,576). `"none"` disables thinking only on 2.5 Flash-class models.
Gemini-specific fields go in a literal JSON key `extra_body: {"google": {"thinking_config": {"thinking_level": "low", "include_thoughts": true}}}`
(REST example) or `extra_body.cached_content`. Thought signatures ride on `tool_calls[].extra_content.google.thought_signature`
(thought-signatures page, "Signatures for OpenAI compatibility"). The layer is still "beta". **Recommendation: use native
generateContent for Gemini**; the OpenAI layer is a fallback only.

**Interactions API (VERIFIED overview + migration guide)**: `POST https://generativelanguage.googleapis.com/v1beta/interactions`,
with `stream: true` in the body (same endpoint). SSE events are typed (`interaction.created`, `interaction.in_progress`,
`step.start`, `step.delta` (`delta.type` = `thought` | `text` | ...), `step.stop`, `interaction.completed` (with `usage`),
`interaction.status_update`, `error`). Requests are **stored by default** (`previous_interaction_id`); opt out with
`store=false`. "While it is now considered legacy, the original generateContent API remains fully supported." "Going
forward, all new models, multimodal capabilities, tools, and agentic features will launch on the Interactions API."
(The migration guide's "before" REST sample shows `content.start` events for `streamGenerateContent`, which is inconsistent
with the reference — UNCERTAIN doc error; ignore it.)

**Model IDs (VERIFIED live, models page)**: Stable: `gemini-3.8-flash`, `gemini-3.8-live`, `gemini-3.8-live-extended-thinking`,
`gemini-3.8-flash-tts`, `gemini-3.8-flash-lite-tts`, `gemini-3.7-flash`, `gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite`,
`gemini-3.1-flash-lite`, `gemini-3.1-flash-image`, `gemini-3.1-flash-lite-image`, `gemini-3-pro-image`, `gemini-3.5-transcribe`
(+`-live`). Preview: `gemini-3.1-pro-preview`, `gemini-3-flash-preview`, `gemini-3.5-live-translate-preview`,
`gemini-3.1-flash-live-preview`, `gemini-3.1-flash-tts-preview`, `gemini-omni-1.1-flash`. 2.5 models (`gemini-2.5-pro|flash|flash-lite`)
are access-limited to existing users. Shut down: `gemini-2.0-flash(-lite)`, `gemini-3-pro-preview`, `gemini-3.1-flash-lite-preview`.
"For any new projects, use our latest models: 3.5 Flash-Lite or 3.8 Flash." Naming: stable `gemini-X.Y-flash`, preview
`...-preview[-MM-YYYY]`, latest alias `gemini-flash-latest` (hot-swapped, 2-week notice). Pi's default Google model is
`gemini-3.1-pro-preview` (`PI/coding-agent/src/core/model-resolver.ts:29`). Pi also treats `gemini-flash-latest` as having
`gemini-3.5-flash`'s capabilities, a stale mapping (`generate-models.ts:1598-1603`). gptr should rely on models.dev's own
entry, whose `gemini-flash-latest` has 3.8's cost/effort (executed `analyze3.R`).

### 2.2 Pi's Gemini adapter: behaviours worth porting (VERIFIED `PI/ai/src/api/google-generative-ai.ts`, `google-shared.ts`)

- Mid-conversation system messages are collapsed into `systemInstruction` (Gemini has no system role in `contents`, `google-shared.ts:192`).
- Stream parse loop (`google-generative-ai.ts:106-252`): for each `part` with `text`, `thought===true` opens/continues a
  thinking block, otherwise a text block (block switches emit `*_end`/`*_start`). For `functionCall`, close the current
  block and emit a complete tool call with its `thoughtSignature`. `finishReason` sets the stop reason, promoted to toolUse
  if any tool call exists. `usageMetadata` is replaced on each chunk (last wins).
- `responseId` is kept from the first chunk (`:108-110`).
- Retries: 408/409/429/5xx with backoff, honouring retry-after (`retryGoogleRequest`, `google-shared.ts:494-515`).

### 2.3 OpenAI Chat Completions adapter in Pi (VERIFIED `PI/ai/src/api/openai-completions.ts`)

This single adapter serves OpenRouter, Groq, Cerebras, DeepSeek, Together, Hugging Face, NVIDIA, Fireworks (some models),
Cloudflare, OpenCode, Moonshot, Z.ai, llama.cpp and any `models.json` custom endpoint. Behaviours (with line numbers):

Request building (`buildParams`, 797-1002):
- `model`, `messages`, `stream: true`; `stream_options: {include_usage: true}` unless `supportsUsageInStreaming === false` (829-831).
- `prompt_cache_key` (session id, clamped) only when `baseUrl` contains `api.openai.com` or long retention is on (821-825);
  `prompt_cache_retention: "24h"` for long retention (826).
- `store: false` when `supportsStore` (833-835).
- Max tokens as `max_tokens` or `max_completion_tokens` per `maxTokensField` (837-844).
- `tools` from the transcript; **`tools: []` when there are no tools but the history contains tool calls/results**
  (855-858; "Anthropic (via LiteLLM/proxy) requires tools param").
- `tool_stream: true` for Z.ai (`zaiToolStream`, 852-854); `tool_choice` passthrough (864-866); vLLM `priority` (868-870).
- Thinking parameter shape by `thinkingFormat` (875-972), detailed in 3.4.
- Optional top-level thinking budget field (974-980), `provider` routing for OpenRouter (983-985), Vercel `providerOptions.gateway` (988-996).
- `samplingParams` from model then request are merged **last**, so they override anything (999).

Message conversion (`convertMessages`, 1185-1472):
- The system prompt role is `developer` iff `model.reasoning && supportsDeveloperRole`, else `system` (1225).
- User content: a string, or parts `[{type:"text"}, {type:"image_url", image_url:{url:"data:<mime>;base64,<data>"}}]`; empty text parts dropped (1253-1282).
- Assistant: **content is a plain string, never an array** (1321-1349; array content made DeepSeek-via-NIM mirror the structure),
  with one exception: when `requiresThinkingAsText` is set, content becomes a text-part array whose first part is the thinking text (1315-1320).
  Thinking replay: `reasoning_details` if present, else the original field name (`reasoning_content`/`reasoning`/`reasoning_text`)
  stored in the thinking block's signature; or plain text if `requiresThinkingAsText` (1302-1342).
  `reasoning_content: ""` is forced when `requiresReasoningContentOnAssistantMessages` (1378-1384).
  Assistant messages with no content and no tool calls are **skipped** (1385-1396).
- Tool calls: `{id, type:"function", function:{name, arguments: JSON string}}` (1352-1374). IDs coming from the Responses API
  in the form `call|item` are sanitised to `[A-Za-z0-9_-]` and capped at 40 chars with a hash suffix; for provider `openai`
  IDs are truncated to 40 (1194-1218).
- Tool results: `{role:"tool", tool_call_id, content: text}`, placeholder `"(see attached image)"` / `"(no tool output)"`;
  `name` added if `requiresToolResultName` (1398-1425). Images in tool results go into a following **user** message
  `[{text:"Attached image(s) from tool result:"}, image_url...]` (1426-1461), preceded by a synthetic assistant message
  `"I have processed the tool results."` if `requiresAssistantAfterToolResult` (1233-1238, 1443-1448).
- All text passes through `sanitizeSurrogates` (lone UTF-16 surrogates removed).

Tools (`convertTools`, 1474-1509): `{type:"function", function:{name, description, parameters, strict?}}`. `strict` is included
only when `supportsStrictMode !== false` ("Some reject unknown fields"). Grammar/custom tools only with `supportsOpenAIGrammarTools`.

Stream parsing (553-700):
- `responseId` from `chunk.id`; `responseModel` if `chunk.model` differs from the requested ID.
- `chunk.usage` → usage (also `choices[0].usage` for Moonshot, 570-574).
- `finish_reason` mapping (1554-1578): `stop`/`end` → stop, `length`, `tool_calls`/`function_call` → toolUse,
  `content_filter`/`network_error`/other → **error** with message `Provider finish_reason: <x>`.
- Text: `delta.content` non-empty (586-600).
- Reasoning: **first non-empty of `reasoning_content`, `reasoning`, `reasoning_text`** ("chutes.ai returns both ...", 602-633).
- Tool calls: keyed by `index`, falling back to `id`; `name` set once; `arguments` concatenated and partially parsed on each delta (635-663).
- `reasoning_details` (OpenRouter) accumulated: consecutive `reasoning.text`/`reasoning.summary` merged, `reasoning.encrypted`
  kept discrete; serialised into the thinking signature at block end (665-676, 243-266).
- End of stream: if `supportsFinishReason === false` and no finish reason, infer toolUse/stop; if it is expected and missing,
  **error "Stream ended without finish_reason"** (690-698).
- Errors: status/aborted → `stopReason = "aborted"|"error"`, message formatted from the body; OpenRouter `error.metadata.raw` appended (702-725).

Usage (`parseChunkUsage`, 1511-1552): `cacheRead = prompt_tokens_details.cached_tokens ?? prompt_cache_hit_tokens (DeepSeek) ?? cached_tokens (Kimi)`;
`cacheWrite = prompt_tokens_details.cache_write_tokens`; `input = max(0, prompt_tokens - cacheRead - cacheWrite)`;
`output = completion_tokens` (already includes reasoning); `reasoning = completion_tokens_details.reasoning_tokens`.

Headers (`createClient`, 752-795): `User-Agent`, model headers, Copilot dynamic headers, then session-affinity headers
(`openrouter`: `x-session-id`; `openai`: `session_id`, `x-client-request-id`, `x-session-affinity`; `openai-nosession`: the latter two),
with request headers merged last.

### 2.4 Per-provider facts and quirks (OpenAI-compatible universe)

Base URLs are from Pi providers (`PI/ai/src/providers/*.ts`, `scripts/generate-models.ts`), models.dev `api`, and provider
docs (VERIFIED unless marked). The full matrix is in 3.5. Highlights:

- **OpenRouter** (`https://openrouter.ai/api/v1`, `OPENROUTER_API_KEY`): Pi detects `thinkingFormat: "openrouter"` →
  `reasoning: {effort}` (or `{effort: "none"}` when off unless the map says `off: null`). The OpenRouter reasoning object also
  accepts `max_tokens`, `exclude`, `enabled`, and effort values `max|xhigh|high|medium|low|minimal|none` (`or_reasoning.md:74-83`).
  Reasoning appears in `message.reasoning` / `delta.reasoning` plus structured `reasoning_details`, which should be passed back
  unmodified for tool use (`:536-617`). SSE keep-alive comments `: OPENROUTER PROCESSING` (`or_streaming.md:219-225`).
  Mid-stream errors arrive as a normal chunk with a top-level `error:{code,message}` and `choices[0].finish_reason:"error"`
  (`:485-496`). **Usage is always included; `stream_options.include_usage` and `usage.include` are deprecated no-ops**
  (`or_usage.md:64-69`), and `usage.cost` is reported in credits. Attribution headers: `HTTP-Referer` (required for attribution)
  plus `X-OpenRouter-Title` (`X-Title` still accepted) (`or_attrib.md:26-45`). Developer role only for `anthropic/*` and
  `openai/*` models; `cache_control` markers for `anthropic/*` (Pi `detectCompat` 1632-1638). Routing: `provider: {order, only,
  ignore, allow_fallbacks, data_collection, zdr, sort, max_price, quantizations, ...}` (`types.ts:975-1019`).
  Model variants use colon suffixes (`:free`, `:extended`, `:exacto`, `:thinking`, `:online`, `:nitro`, `:floor`) and `~`-prefixed
  aliases (`~anthropic/claude-sonnet-latest`). None of these suffixes collide with gptr's thinking levels.
- **Groq** (`https://api.groq.com/openai/v1`, `GROQ_API_KEY`): 400 errors for `logprobs`, `logit_bias`, `top_logprobs`,
  **`messages[].name`**; `n` must be 1; `temperature: 0` becomes `1e-8` (`groq_openai.md`). Reasoning (live docs): `reasoning_format`
  `parsed|raw|hidden` for non-gpt-oss models, `include_reasoning` for gpt-oss (mutually exclusive); `reasoning_effort` values are
  model-specific (qwen: `none|default|low|medium|high`; gpt-oss: `low|medium|high`); output in `message.reasoning` / `delta.reasoning`;
  `raw` + JSON mode/tools → 400. Pi's catalog maps `groq/qwen/qwen3.6-27b` high→`"default"` (`generate-models.ts:1129-1131`).
- **Cerebras** (`https://api.cerebras.ai/v1`, `CEREBRAS_API_KEY`): Pi's detection marks it non-standard (no `store`, no
  developer role). Docs: `n` must be 1; no external image URLs or `image_url.detail`; don't send `tool_stream`; reasoning in
  `delta.reasoning`; **replay `reasoning` on assistant messages**; `clear_thinking` drops history reasoning; `reasoning_effort`
  per model (qwen-3.8-27b `none|low|medium|high`, gpt-oss-120b `low|medium|high`).
- **xAI** (`https://api.x.ai/v1`, `XAI_API_KEY`): Pi uses the **Responses API** for xAI (`providers/xai.ts`), because Chat
  Completions "has no field for the ciphertext" of encrypted reasoning (live reasoning doc). `reasoning_effort` on grok-4.5/4.6/4.7
  (`low|medium|high|xhigh`); `presencePenalty`, `frequencyPenalty`, `stop` unsupported on reasoning models. Pi's
  `detectCompat` marks `api.x.ai` as non-standard with `supportsReasoningEffort: false` (a legacy grok-3 rule), and sets
  `supportsLongCacheRetention: false` for xAI Responses (`generate-models.ts:471-473`).
- **DeepSeek** (`https://api.deepseek.com`, `DEEPSEEK_API_KEY`): thinking `{"thinking": {"type": "enabled"|"disabled"}}`,
  `reasoning_effort` `low|high|max`, reasoning in `reasoning_content`. **With tools, all previous turns' `reasoning_content` must be
  passed back, otherwise 400; without tools it is ignored** (live thinking-mode doc). Thinking mode ignores `temperature`,
  `presence_penalty`, `frequency_penalty` (doc: "setting these parameters will not trigger an error but will also have no effect");
  `top_p` is floored at 0.95. Thinking is on by default with default effort `high`. Pi: `thinkingFormat:"deepseek"`,
  `requiresReasoningContentOnAssistantMessages: true`, `max_tokens` field (`generate-models.ts:3071-3074`, `detectCompat`).
  models.dev marks such models `interleaved: {field: "reasoning_content"}`.
- **Mistral** (`https://api.mistral.ai`, path `v1/chat/completions`, `MISTRAL_API_KEY`): Pi uses a dedicated adapter
  (`mistral-conversations.ts`) because tool-call IDs must be **exactly 9 alphanumeric characters** (`:28`, derived by hashing,
  `:259-267`); thinking arrives as content chunks `{type:"thinking", thinking:[{type:"text", text}]}` (`:45`, `:653-670`);
  reasoning is `prompt_mode: "reasoning"` (Magistral) or `reasoning_effort` (models with an effort map, `:196-215`); prompt-cache
  affinity header `x-affinity` (`:340-356`). Live docs: `reasoning_effort` values `none|minimal|low|medium|high|xhigh`,
  `tool_choice` `auto|none|any|required|{function}`. gptr can treat Mistral as OpenAI-compatible with a `mistral` compat profile
  (9-char IDs + content-array thinking).
- **Together** (`https://api.together.ai/v1`; Pi also detects `api.together.xyz`; `TOGETHER_API_KEY`): `reasoning: {enabled: bool}`
  toggle, `reasoning_effort` only on some models (gpt-oss `low|medium|high`; DeepSeek V4 Pro `high|max`); reasoning in `reasoning`
  or `reasoning_content` depending on the model; **DeepSeek-R1 uses `<think>` tags in `content`**; `logit_bias` unsupported;
  "pass the reasoning content back using the same field key" (live docs). Pi's Together compat: no store, no developer role,
  `max_tokens`, no strict, no long cache, `thinkingFormat: "together"` (`generate-models.ts:173-222`).
- **Fireworks** (`FIREWORKS_API_KEY`): OpenAI-compatible at `https://api.fireworks.ai/inference/v1`, Anthropic-compatible at
  `https://api.fireworks.ai/inference` (the SDK appends `/v1/messages`). Pi routes most models to anthropic-messages and GLM/Kimi-K3
  to completions, with session-affinity headers and no store/developer role (`generate-models.ts:1670-1754`). Model IDs look like
  `accounts/fireworks/models/<name>`.
- **Hugging Face router** (`https://router.huggingface.co/v1`, `HF_TOKEN`): provider-selection suffixes on the model ID
  (`:fastest` default, `:cheapest`, `:preferred`, or a provider name, e.g. `openai/gpt-oss-120b:cheapest`) (`hf_router.md:125-127`).
  Pi sets `supportsDeveloperRole: false` (`generate-models.ts:2144-2146`).
- **NVIDIA NIM** (`https://integrate.api.nvidia.com/v1`, `NVIDIA_API_KEY`): header `NVCF-POLL-SECONDS: 3600`; compat
  `{store:F, developer:F, reasoning_effort:F, max_tokens, strict:F, long cache:F}` (`generate-models.ts:230-241`).
- **Ollama** (local `http://localhost:11434/v1`, key "required but ignored", e.g. `"ollama"`; cloud `https://ollama.com/v1` with
  `OLLAMA_API_KEY`): supported fields include `stream_options.include_usage`, `tools`, `reasoning_effort`, `reasoning.effort`,
  `max_tokens`, `response_format`, `seed`, `stop`. **Not supported**: image URLs (base64 only), `tool_choice`, `logit_bias`, `user`,
  `n`, logprobs (`ollama_openai2.md:205-249`). Effort names are model-defined (`/api/show`); `minimal`→`low`, `xhigh|ultra`→`max`
  aliases. Reasoning text arrives in the `reasoning` field (LIKELY: search results + Pi's generic handling; not in the saved doc).
  The native API (`/api/chat`, `/api/tags`, `/api/show`, `think`, `keep_alive`, `options.num_ctx`) is richer but not needed.
- **LM Studio** (`http://localhost:1234/v1`): `/v1/models`, `/v1/responses`, `/v1/chat/completions`, `/v1/embeddings`,
  `/v1/completions` (`lmstudio_openai.md`). models.dev lists env `LMSTUDIO_API_KEY` (optional).
- **llama.cpp server** (`http://127.0.0.1:8080`, OpenAI routes under `/v1`, optional `--api-key`/env `LLAMA_API_KEY`):
  tools need `--jinja` (default enabled in current builds); `--reasoning-format none|deepseek|deepseek-legacy` (default `auto`):
  `deepseek` puts reasoning in `reasoning_content`, `none` leaves thoughts unparsed in `content`, `deepseek-legacy` keeps `<think>`
  tags in `content` *and* fills `reasoning_content` (live README, 2026-09-29); request extras `chat_template_kwargs` (e.g. `{"enable_thinking": false}`), `reasoning_effort`
  (`none` disables), `reasoning_format`, `parse_tool_calls`, `parallel_tool_calls`; `image_url.url` may be remote, base64 or
  `file://` path; health at `GET /health` (no auth); `GET /props`, `GET /v1/models`; router mode with `/models/load`,
  `/models/unload` (`llamacpp_server_README.md:212-239, 470, 1309-1345, 1441`). It also serves an Anthropic Messages endpoint
  (`:1603`). Pi's llama.cpp extension maps each model to `openai-completions` with
  `{supportsStore:false, supportsDeveloperRole:false, supportsReasoningEffort:false, supportsUsageInStreaming:true, supportsStrictMode:false, maxTokensField:"max_tokens"}`
  plus `thinkingFormat: "qwen-chat-template"` when `/props` `chat_template` contains `enable_thinking`, and a context window from
  `meta.n_ctx` (`PI/coding-agent/src/extensions/llama/provider.ts:100-130`). Env `LLAMA_BASE_URL`/`LLAMA_API_KEY` (`docs/llama-cpp.md:58-64`).
- **vLLM** (`http://localhost:8000/v1`, `--api-key` / `VLLM_API_KEY`): "`reasoning` used to be called `reasoning_content`"
  (`vllm_reasoning.md:8-9`); reasoning needs `--reasoning-parser <name>`; Qwen3/Granite/Gemma toggles via
  `chat_template_kwargs` (`enable_thinking`/`thinking`); `thinking_token_budget`; tools need
  `--enable-auto-tool-choice --tool-call-parser <p>`; `tool_choice` `auto|required|none|named`; `image_url.detail` unsupported;
  `top_k` etc. via extra body fields (`vllm_tools.md`, `vllm_openai.md`). Pi flags: `thinkingTokenBudgetField:"thinking_token_budget"`, `vllmPriority`.

Pi's `models.json` (docs `models.md:45-66`) shows the minimal local config:
`{"providers":{"ollama":{"baseUrl":"http://localhost:11434/v1","api":"openai-completions","apiKey":"ollama","models":[{"id":"qwen2.5-coder:7b"}]}}}`.
"Compatibility settings should describe verified differences ... Do not enable them based only on an endpoint advertising
OpenAI or Anthropic compatibility" (`models.md:101`).

### 2.5 Azure OpenAI (VERIFIED MS Learn "v1 API" page, `SCR/web/azure_lifecycle.html.txt`; Pi `azure-openai-responses.ts`)

- v1 GA API: base `https://YOUR-RESOURCE-NAME.openai.azure.com/openai/v1/` (also `https://YOUR-RESOURCE-NAME.services.ai.azure.com/openai/v1/`);
  "api-version is no longer a required parameter with the v1 GA API". Standard `OpenAI()` clients work with that `base_url`.
- Auth: `api-key: $AZURE_OPENAI_API_KEY` (curl example) or `Authorization: Bearer <Entra ID token>` (scope `https://ai.azure.com/.default`).
- `model` is the **deployment name**. Both `/responses` (recommended for Azure OpenAI models) and `/chat/completions`
  (also for Foundry models like DeepSeek, Grok, MAI-DS-R1) are available.
- Preview features use per-feature headers (e.g. `"aoai-evals":"preview"`) or `alpha` in the path, instead of dated api-versions.
- Pi: `DEFAULT_AZURE_API_VERSION = "v1"` (`:25`); base URL from `AZURE_OPENAI_BASE_URL`, else
  `https://${AZURE_OPENAI_RESOURCE_NAME}.openai.azure.com/openai/v1`, else `model.baseUrl` (`:226-259`); root URLs under
  `*.openai.azure.com`, `*.cognitiveservices.azure.com`, `*.ai.azure.com` with empty, `/openai` or `/openai/v1/responses` paths are
  normalised to `/openai/v1` (`:191-220`); deployment mapping `AZURE_OPENAI_DEPLOYMENT_NAME_MAP="model=deployment,model2=dep2"` (`:30-51`);
  Responses minimum `max_output_tokens` 16 (`:27-28`).
- models.dev has `azure` (env `AZURE_RESOURCE_NAME, AZURE_API_KEY`, 94 models) and `azure-cognitive-services`.
  Pi's env names differ (`AZURE_OPENAI_*`); gptr should accept both.

### 2.6 Amazon Bedrock

Three access paths (VERIFIED AWS docs in `SCR/web/bedrock_*.txt`):

1. **OpenAI-compatible Chat Completions on bedrock-runtime** (recommended endpoint):
   `https://bedrock-runtime.{region}.amazonaws.com/openai/v1/chat/completions`, auth "AWS credentials (SigV4) or Amazon Bedrock API key".
   It does **not** implement `GET /models`; use ListFoundationModels. Example model `openai.gpt-oss-120b-1:0`. A second
   "compatibility" endpoint `https://bedrock-mantle.{region}.api.aws/v1/chat/completions` supports `/v1/models`.
   Guardrails via headers `X-Amzn-Bedrock-GuardrailIdentifier`, `X-Amzn-Bedrock-GuardrailVersion`, `X-Amzn-Bedrock-Trace` and body
   field `amazon-bedrock-guardrailConfig`. The page's navigation also lists Responses API and **Messages API** (Anthropic-compatible)
   pages (UNCERTAIN on their details; not fetched).
2. **Converse / ConverseStream with a Bedrock API key**: `POST https://bedrock-runtime.{region}.amazonaws.com/model/{modelId}/converse`
   (or `/converse-stream`), header `Authorization: Bearer $AWS_BEARER_TOKEN_BEDROCK`. API keys are limited to Bedrock and Bedrock
   Runtime actions (not bidirectional streaming, Agents, Data Automation). `AWS_BEARER_TOKEN_BEDROCK` is also read by the SDKs.
3. **Converse with IAM credentials**: SigV4 (service `bedrock`, region from `AWS_REGION`/`AWS_DEFAULT_REGION`/profile).

ConverseStream (VERIFIED API reference): request `{messages, system, inferenceConfig{maxTokens, stopSequences, temperature, topP},
toolConfig{tools, toolChoice}, additionalModelRequestFields, additionalModelResponseFieldPaths, guardrailConfig, outputConfig,
performanceConfig, promptVariables, requestMetadata, serviceTier}`. Response event union members: `messageStart{role}`,
`contentBlockStart{contentBlockIndex, start}`, `contentBlockDelta{contentBlockIndex, delta}`, `contentBlockStop{contentBlockIndex}`,
`messageStop{stopReason, additionalModelResponseFields}`, `metadata{usage, metrics{latencyMs}, trace, performanceConfig, serviceTier}`,
plus exceptions (`internalServerException`, throttling, validation, ...). Requires permission `bedrock:InvokeModelWithResponseStream`.
Model IDs can be base IDs, inference-profile IDs (`us.anthropic.claude-sonnet-4-6`) or ARNs (regex in the reference).

The wire framing is **AWS event stream** (Smithy spec, VERIFIED): each message is
`uint32 total_length | uint32 headers_length | uint32 prelude_crc | headers | payload | uint32 message_crc`, big-endian,
CRC32 (IEEE/gzip) over the prelude and over everything before the message CRC. Headers:
`uint8 name_len | name | uint8 type | value`, with types 0 true, 1 false, 2 byte (**signed** int8), 3 short (signed int16),
4 int (signed int32), 5 long (signed int64), 6 bytes (u16 len), 7 string (u16 len), 8 timestamp (8-byte unsigned, ms since epoch),
9 uuid (16 bytes). Limits: payload ≤ 24 MB, headers ≤ 128 KB. Semantics: `:message-type`
= `event` (+`:event-type`), `exception` (+`:exception-type`), or `error` (+`:error-code`, `:error-message`); `:content-type` optional.

Pi uses the AWS SDK (`@aws-sdk/client-bedrock-runtime` + smithy) with `bearerToken` bypassing SigV4
(`bedrock-converse-stream.ts:105-110, 180-239`), region precedence ARN-embedded > option > env > endpoint > `us-east-1`
(`:191-202`), `AWS_PROFILE`, ECS/IRSA credential sources (`docs/providers.md:117-139`). The catalog skips `ai21.jamba*`
("doesn't support tool use in streaming mode") and `mistral.mistral-7b-instruct-v0*` (no system messages) (`generate-models.ts:1775-1783`).

**Cost of SigV4 in pure R — assessed and prototyped (VERIFIED)**:
- ~85 lines of R using only `openssl::sha256()` (hash and HMAC); no digest needed (`SCR/v2/sigv4.R`).
- Matches the official AWS test suite (`awslabs/aws-c-auth`) `get-vanilla` → `5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31`
  and `post-x-www-form-urlencoded` → `d3875051da38690788ef43de4db0d8f280229d82040bfac253562e56c3f20e0b`.
- Matches libcurl's `CURLOPT_AWS_SIGV4` (`curl::new_handle(aws_sigv4 = "aws:amz:us-east-1:bedrock", userpwd = "AK:SK")`)
  byte-for-byte on a Bedrock-shaped POST, for model IDs with a raw `:` and with `%3A` (canonical URI encodes the path *as sent*,
  so `%3A` becomes `%253A`; this is the well-known Bedrock colon pitfall).
- libcurl ≥ 7.75 exposes `aws_sigv4`, and it is available here (libcurl 8.14.1). Windows CRAN builds of curl ship a recent
  libcurl (LIKELY available); old Linux system libcurl (< 7.75) lacks it. So keep the pure-R signer as the portable path and
  optionally prefer libcurl when `"aws_sigv4" %in% names(curl::curl_options())`.
- Credential *discovery* (profiles in `~/.aws/credentials` INI, SSO, IMDS, ECS, web identity) is the expensive part.
  Recommendation: env vars + `AWS_BEARER_TOKEN_BEDROCK` in core, and `aws.signature`/`paws.common` (CRAN) in Suggests for profile/SSO chains.
- Eventstream decoding in pure R: ~90 lines, CRC32 table in R (verified against the check value `cbf43926` and `digest::digest(algo="crc32")`),
  ~190 KB/s throughput in pure R. That is ample for token streams; `digest` in Suggests can accelerate the CRC.

### 2.7 GitHub Copilot (brief; VERIFIED Pi source)

- Auth: GitHub OAuth **device code** flow (`https://{domain}/login/device/code`, `.../login/oauth/access_token`, scope
  `read:user`) with a VS Code client ID embedded (obfuscated) in Pi, then exchange at
  `https://api.{domain}/copilot_internal/v2/token` for a short-lived token `tid=...;exp=...;proxy-ep=proxy.individual.githubcopilot.com;...`.
  The API base is derived from `proxy-ep` (`https://api.individual.githubcopilot.com` by default; enterprise `https://copilot-api.{domain}`)
  (`PI/ai/src/auth/oauth/github-copilot.ts:58-86, 216-344`). Env shortcut `COPILOT_GITHUB_TOKEN`.
- Static headers: `User-Agent: GitHubCopilotChat/0.35.0`, `Editor-Version: vscode/1.107.0`, `Editor-Plugin-Version: copilot-chat/0.35.0`,
  `Copilot-Integration-Id: vscode-chat` (`generate-models.ts:166-171`). Dynamic headers: `X-Initiator: user|agent`,
  `Openai-Intent: conversation-edits`, `Copilot-Vision-Request: true` when images are present (`github-copilot-headers.ts`).
- Routing: Claude 4.x/5.x → Anthropic Messages; `gpt-*`, `grok-*`, `oswe*`, `mai-*` → Responses; others → Chat Completions with
  `{store:F, developer:F, reasoning_effort:F}` (`generate-models.ts:2341-2393`).
- Recommendation: **do not ship in core**. Impersonating an editor client ID and headers is a terms-of-service risk (see
  report 03 §2.13). If wanted, provide it as an opt-in extension.

### 2.8 Model catalog: where Pi gets metadata, and the models.dev schema

Pi (VERIFIED; details also in report 03 §2.10): build-time `scripts/generate-models.ts --strict` fetches
`https://models.dev/api.json` (`:1759`), `https://models.dev/models.json?type=decision` (System-1 models), OpenRouter
`/api/v1/models` (plus `?output_modalities=image` and `?output_modalities=decisions`, `:1300-1325`), Vercel AI Gateway `/v1/models`,
NVIDIA `/v1/models`, and the Radius config. It keeps only `tool_call === true` models and applies hundreds of lines of verified
corrections (compat flags, thinking maps, prices, missing models). At run time it overlays
`https://pi.dev/api/models/providers/<id>?types=chat,image,classifier` every 4 h (`remote-catalog-provider.ts:15`), with ETag;
`pi update --models` forces a refresh. Local servers (llama.cpp) are discovered live from `/models` + `/props`.

models.dev (VERIFIED executed, 2026-09-29 18:36 local):
- `GET https://models.dev/api.json` → 200, 5,263,829 bytes, `content-type: application/json`, `content-encoding: gzip`,
  `cache-control: public, max-age=0, must-revalidate`, `etag: W/"a174062643509bd51dc6338a3e8bb26a"`, `access-control-allow-origin: *`.
  Re-request with `If-None-Match` → **304**, 0 bytes. (Verifier re-fetch at 19:11 the same day: identical 5,263,829 bytes and counts,
  but a *different* ETag `W/"e2c7ccfcd2315060e1baf90f68c66a6e"` because 7 bytes of price data had changed in ~35 minutes; again 304
  on revalidation. The catalog changes often, so always store the ETag from the latest 200 and do not treat a size match as "unchanged".)
- Structure: a named object of **225 providers**, **8,323 models** total. Provider fields: `id, env[], npm, name, doc` (all 225),
  `api` (199; base URL for `@ai-sdk/openai-compatible` providers), `models` (named object keyed by model ID).
- `GET /models.json` → 402,067 bytes, 434 entries keyed by canonical ID (`"bytedance-seed/seed-2.0-pro"`), provider-agnostic
  metadata (no cost). `GET /catalog.json` → 5,665,920 bytes, `{providers, models}`. `GET /models.json?type=decision` → 450 bytes,
  one entry `typesafe/jev-latest` (`type:"decision"`, context 64000). Logos: `/logos/{provider}.svg`.
- License: MIT ("Models.dev is created by the maintainers of SST", GitHub `sst/models.dev`), so redistributing a snapshot is
  allowed with attribution. Keep the license notice in `inst/COPYRIGHTS` or the snapshot's `_meta`.
- The per-field schema with counts is in 3.8.

Semantics worth using in gptr:
- `reasoning_options` (6,134 models): `{type:"effort", values:[...]}` (3,813), `{type:"toggle"}` (1,377),
  `{type:"budget_tokens", min, max}` (598). Pi converts effort values into a `thinkingLevelMap`: `none` → `off`,
  and each of `minimal..max` supported or `null` (`scripts/models-dev-reasoning-options.ts:18-30`).
- `interleaved`: `true` (103) or `{field:"reasoning_content"}` (1,099) / `{field:"reasoning_details"}` (15). This tells which field
  must be **replayed** on assistant messages, the data-driven equivalent of Pi's `requiresReasoningContentOnAssistantMessages`.
- `provider` (model-level override, 339): `npm` (333), `api` (174, base URL), `shape` (`responses` 36, `completions` 8), i.e.
  which wire API a model on an aggregator uses.
- `cost`: USD per million tokens `input, output, cache_read (5,359), cache_write (1,767), reasoning (152), input_audio (135),
  output_audio (18)`, `tiers[{input,output,cache_read, tier:{type:"context", size}}]` (606), legacy `context_over_200k` (511).
- `experimental.modes` (55): e.g. `claude-opus-5-5` has `fast` with a separate cost and `provider:{body:{speed:"fast"}, headers:{anthropic-beta:"fast-mode-2026-02-01"}}`.
- `canonical_model_id` (5,257): e.g. `anthropic/claude-sonnet-5-5`; its provider part identifies the **owner** (used for tie-breaking, 2.9).
- `status`: `beta` (72), `deprecated` (252). `limit.input` (1,433) exists where input differs from context.
- `family` (7,627): e.g. `claude-sonnet`, `gemini-flash`, used for dynamic aliases.

### 2.9 Model names in Pi and in R

Pi's resolver (VERIFIED `PI/coding-agent/src/core/model-resolver.ts`):
- Exact reference: case-insensitive `provider/id`; then `provider` + `id` split at the first `/`; then a unique bare ID.
  Ambiguous bare IDs are rejected (`:88-130`).
- Fuzzy: substring on id or name; prefer "aliases" (IDs without a `-YYYYMMDD` suffix, or ending in `-latest`) sorted descending,
  else the latest dated version (`:136-166`).
- Thinking suffix: try the whole pattern first; if nothing matches and it has a colon, split at the **last** colon; if the suffix
  is a valid level (`off, minimal, low, medium, high, xhigh, max`, `cli/args.ts:60`) recurse on the prefix (`:204-257`). This keeps
  OpenRouter `:exacto` and Ollama `llama3.1:8b` working.
- CLI: prefer interpreting `x/...` as provider `x` when `x` is a known provider, fall back to the raw ID across all providers
  (OpenRouter-style `openai/gpt-4o:extended`); with multiple exact matches prefer the single authenticated provider, otherwise
  error "ambiguous" (`:444-503`). Unknown ID under a known provider → a fallback model cloned from the provider default with
  the custom ID and a warning (`:175-189, 570-596`).
- Clamping a requested level to what the model supports: search upward first, then downward (`PI/ai/src/models.ts:1215-1249`).

R NSE behaviour (VERIFIED executed, 5.7): `substitute(model)` gives a symbol for `sonnet`, and calls for `a/b-c` and `a:b`.
`gsub("[[:space:]]", "", deparse(e))` recovers `anthropic/claude-sonnet-5-5`, `google/gemini-3.8-flash`, `claude-opus-5-5:xhigh`,
`ollama/llama3`. Lossy: `openai/gpt-5.10` → `openai/gpt-5.1`, `a/b-1e3` → `a/b-1000`. Parse errors (cannot be caught by the
callee): `groq/openai/gpt-oss-120b`, `x/gemma4:31b` (tokens like `120b`). Backquoted names survive intact.

### 2.10 Streaming in R: transports, latency and encoding (VERIFIED executed; code and output in 5.1-5.2)

- httr2 1.2.2 reads SSE through `resp_boundary_pushback()`, which calls `resp$body$read(min(max_size + 1, 1024))`
  (printed source). On a **blocking** curl connection that read returns only when the requested byte count is available or at EOF.
  Measured with a server sending ~150-byte events every 250 ms: 1024-byte reads → first data at **1.30 s**, 2 reads total;
  256-byte reads → first at 0.26 s; 64-byte reads → first at 0.00 s and every 0.25 s (5.2).
- Consequence: `req_perform_connection(blocking = TRUE)` + `resp_stream_sse()` gave median inter-event gap 0.00 s and max 1.53 s
  (OpenAI mock) / 0.76 s (Gemini mock), i.e. bursts. ellmer 0.4.0's synchronous `chat_perform_stream()` uses exactly this
  (printed source). Its async path uses `blocking = FALSE` + `later::later_fd()`.
- `curl::multi_add(data = callback)` + `curl::multi_run(timeout = 0.05, poll = TRUE)` and httr2 `blocking = FALSE` +
  `resp_stream_raw()` polling both delivered events at their true ~0.25 s spacing, with identical parsed results.
- httr2's own SSE parser marks data as UTF-8 correctly (`parse_event`: `Encoding(str_data) <- "UTF-8"`); the earlier mojibake
  came from the mock server's non-ASCII *source literals* being parsed in a C locale. Rule for gptr sources and tests: keep R
  files ASCII and build non-ASCII strings with `intToUtf8()` or `\u` escapes.

---

## 3. Exact specifications

### 3.1 Gemini generateContent (REST)

Streaming request (the exact body my client sent to the mock; valid per the reference):
```http
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse
x-goog-api-key: <GEMINI_API_KEY>
Content-Type: application/json
Accept: text/event-stream

{"systemInstruction":{"parts":[{"text":"You are terse."}]},
 "contents":[{"role":"user","parts":[{"text":"Summarise mtcars$mpg"}]}],
 "tools":[{"functionDeclarations":[{"name":"r_eval","description":"Evaluate R code",
   "parametersJsonSchema":{"type":"object","properties":{"code":{"type":"string"}},"required":["code"]}}]}],
 "toolConfig":{"functionCallingConfig":{"mode":"AUTO"}},
 "generationConfig":{"maxOutputTokens":1024,"thinkingConfig":{"includeThoughts":true,"thinkingLevel":"low"}}}
```
For Gemini 2.5 use `"thinkingConfig":{"includeThoughts":true,"thinkingBudget":8192}` (`0` = off, `-1` = dynamic).

Replaying a tool round (Gemini 3; signature on the first call only; IDs echoed):
```json
{"contents":[
 {"role":"user","parts":[{"text":"Check the weather in Paris and London."}]},
 {"role":"model","parts":[
   {"functionCall":{"id":"fc_1","name":"get_current_temperature","args":{"city":"Paris"}},"thoughtSignature":"<Signature_A>"},
   {"functionCall":{"id":"fc_2","name":"get_current_temperature","args":{"city":"London"}}}]},
 {"role":"user","parts":[
   {"functionResponse":{"id":"fc_1","name":"get_current_temperature","response":{"output":"15C"}}},
   {"functionResponse":{"id":"fc_2","name":"get_current_temperature","response":{"output":"12C"}}}]}]}
```
Error variant: `"response":{"error":"<message>"}`. Multimodal result (Gemini 3):
`{"functionResponse":{"name":"get_image","id":"...","response":{"image_ref":{"$ref":"instrument.jpg"}},"parts":[{"inlineData":{"displayName":"instrument.jpg","mimeType":"image/jpeg","data":"<b64>"}}]}}`.

Replaying thinking (same model only): `{"thought":true,"text":"<summary>","thoughtSignature":"<sig>"}`; text with signature:
`{"text":"...","thoughtSignature":"<sig>"}`.

Stream events (shape emitted by my mock, following the reference; Gemini sends one JSON object per `data:` line, no event name, no `[DONE]`):
```
data: {"candidates":[{"content":{"parts":[{"text":"**Planning** ...","thought":true}],"role":"model"},"index":0}],"modelVersion":"...","responseId":"..."}

data: {"candidates":[{"content":{"parts":[{"text":"I will look at ..."}],"role":"model"},"index":0}],...}

data: {"candidates":[{"content":{"parts":[{"functionCall":{"id":"fc_1","name":"r_eval","args":{"code":"summary(mtcars$mpg)"}},"thoughtSignature":"c2lnLWZjMQ=="},
                                         {"functionCall":{"id":"fc_2","name":"read_file","args":{"path":"R/a.R"}}}],"role":"model"},
                      "finishReason":"STOP","index":0}],
       "usageMetadata":{"promptTokenCount":120,"cachedContentTokenCount":100,"candidatesTokenCount":25,"thoughtsTokenCount":40,"totalTokenCount":185}}
```
Normalised usage from that: `input 20, output 65, cache_read 100, reasoning 40` (prototype output, 5.1).

Stop-reason mapping for gptr: `STOP` → `stop` (→ `tool_use` if any functionCall), `MAX_TOKENS` → `length`, any other value
(including unknown future values) → `error` with `finishMessage` if present; stream end without `finishReason` → `error`.
A prompt block has no candidates and `promptFeedback.blockReason` set → `error`.

Error body: `{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}`
(the message is the mock's; the shape is Google's standard).

### 3.2 OpenAI Chat Completions streaming (as consumed by the generic client)

Request:
```http
POST {base_url}/chat/completions
Authorization: Bearer <key>          (Azure key auth: "api-key: <key>")
Content-Type: application/json
Accept: text/event-stream

{"model":"...","messages":[{"role":"system"|"developer","content":"..."},{"role":"user","content":[{"type":"text","text":"..."},{"type":"image_url","image_url":{"url":"data:image/png;base64,..."}}]},
 {"role":"assistant","content":"...","tool_calls":[{"id":"call_1","type":"function","function":{"name":"r_eval","arguments":"{\"code\":\"1+1\"}"}}],"reasoning_content":"..."},
 {"role":"tool","tool_call_id":"call_1","content":"2"}],
 "tools":[{"type":"function","function":{"name":"r_eval","description":"...","parameters":{...}}}],
 "stream":true,"stream_options":{"include_usage":true},"max_completion_tokens":4096}
```
Chunk grammar: `data: {"id","object":"chat.completion.chunk","created","model","choices":[{"index":0,"delta":{"role"?,"content"?,"reasoning_content"|"reasoning"|"reasoning_text"?,"tool_calls"?:[{"index","id"?,"type"?,"function":{"name"?,"arguments"?}}],"reasoning_details"?},"finish_reason":null|"stop"|"length"|"tool_calls"|"content_filter"|"error"}],"usage"?:{...},"error"?:{...}}`,
terminated by `data: [DONE]` (**optional in practice**: my mock's tools scenario omits it, and the client must treat EOF after a
finish reason as success). Usage arrives in a final chunk with `choices: []`.

### 3.3 `OpenAICompletionsCompat` — every flag (VERIFIED `PI/ai/src/types.ts:789-866`, applied in `openai-completions.ts`)

"Default (detected)" is from `detectCompat()` (`openai-completions.ts:1585-1682`); explicit `model.compat` overrides field by
field (`getCompat`, `:1688-1726`).

| Flag | Type | Default (detected) | Effect | Where |
|---|---|---|---|---|
| `supportsStore` | bool | `!isNonStandard` | send `store: false` | 833-835 |
| `supportsDeveloperRole` | bool | OpenRouter `anthropic/*`,`openai/*`; else `!isNonStandard && !isOpenRouter` | system prompt role `developer` (only if `model.reasoning`) vs `system` | 1225 |
| `supportsReasoningEffort` | bool | false for xAI, Z.ai, Moonshot, Together, CF AI Gateway, NVIDIA, Ant Ling | allow `reasoning_effort` | 881-972 |
| `supportsUsageInStreaming` | bool | true | send `stream_options:{include_usage:true}` | 829-831 |
| `supportsFinishReason` | bool | true | if false: infer stop/toolUse at EOF; if true and missing: error | 690-698 |
| `maxTokensField` | `max_completion_tokens`\|`max_tokens` | `max_tokens` for chutes, DeepSeek, Moonshot, CF gateway, Together, NVIDIA, Ant Ling, Z.ai | name of the max-tokens field | 837-844 |
| `requiresToolResultName` | bool | false | add `name` to `role:"tool"` messages | 1421-1423 |
| `requiresAssistantAfterToolResult` | bool | false | insert `{"role":"assistant","content":"I have processed the tool results."}` between tool results and a user message; assistant `content:""` instead of `null` | 1233-1238, 1287, 1443-1448 |
| `requiresThinkingAsText` | bool | false | replay thinking as a plain text part | 1315-1320 |
| `requiresReasoningContentOnAssistantMessages` | bool | DeepSeek | force `reasoning_content: ""` on replayed assistant messages of reasoning models | 1378-1384 |
| `thinkingFormat` | enum (see 3.4) | deepseek / zai / together / ant-ling / openrouter / openai | request shape for thinking | 875-972 |
| `chatTemplateKwargs` | record, values literal or `{"$var":"thinking.enabled"\|"thinking.effort"\|"thinking.budget", omitWhenOff?}` | `{}` | `chat_template_kwargs` for `chat-template` format | 901-905, 1026-1067 |
| `chatTemplateArgs` | same | `{}` | `chat_template_args` for `baseten` | 906-922 |
| `openRouterRouting` | object | `{}` | body field `provider` | 983-985 |
| `vercelGatewayRouting` | `{only?, order?}` | `{}` | `providerOptions.gateway` | 988-996 |
| `zaiToolStream` | bool | false | `tool_stream: true` | 852-854 |
| `thinkingTokenBudgetField` | `thinking_token_budget` (vLLM) \| `thinking_budget` (Qwen/DashScope/SGLang) \| `thinking_budget_tokens` (llama.cpp) | unset | top-level budget, clamped so answer room remains | 974-980, 1012-1024 |
| `supportsThinkingTokenBudget` | bool | false | alias for `thinking_token_budget` | 1004-1010 |
| `supportsOpenAIGrammarTools` | bool | false | emit `{type:"custom", custom:{format:{type:"grammar"...}}}` tools | 1479-1494 |
| `supportsMidConvoSystemMessages` | bool | false | keep later system messages in place, else fold into the leading one | 305, 1191 |
| `supportsMidConvoToolAdditions` | bool | false | Kimi-style `{"role":"system","tools":[...]}` messages | 1241-1248 |
| `supportsStrictMode` | bool | false | include `strict` in function tools | 1497-1506 |
| `cacheControlFormat` | `"anthropic"` | OpenRouter `anthropic/*` (provider id `openrouter` only; not URL-detected) | `cache_control:{type:"ephemeral", ttl?}` on system, last tool, last user/assistant/tool text | 860-862, 1069-1183 |
| `sendSessionAffinityHeaders` | bool | OpenRouter | send session headers from `sessionId` | 771-781 |
| `sessionAffinityFormat` | `openai` \| `openai-nosession` \| `openrouter` | openrouter / openai | which headers (2.3) | 771-781 |
| `supportsLongCacheRetention` | bool | false for Together, CF Workers AI/Gateway, NVIDIA, Ant Ling | `prompt_cache_retention:"24h"` / `ttl:"1h"` | 826, 1077 |
| `vllmPriority` | number | unset | body `priority` | 868-870 |

`isNonStandard` = NVIDIA, Cerebras, xAI (`provider=="xai"` or `api.x.ai`), Together, chutes.ai, DeepSeek, Z.ai, Moonshot, OpenCode,
Cloudflare Workers AI/Gateway, Ant Ling (`:1605-1619`). Hosts: Z.ai `api.z.ai`/`open.bigmodel.cn`; Together `api.together.ai`/`api.together.xyz`;
Moonshot `api.moonshot.`; OpenRouter `openrouter.ai`; CF `api.cloudflare.com`/`gateway.ai.cloudflare.com`; NVIDIA
`integrate.api.nvidia.com`; Cerebras `cerebras.ai`; DeepSeek `deepseek.com` (case-insensitive) (`:1589-1603`).

Other compat families (VERIFIED `types.ts:869-967`): `OpenAIResponsesCompat` (`supportsDeveloperRole`, `supportsMidConvoSystemMessages`,
`sessionAffinityFormat`, `supportsLongCacheRetention`, `supportsStrictMode`, `supportsOpenAIGrammarTools`, `supportsAdditionalTools`,
`supportsToolSearch`, `supportsExplicitPromptCacheMode`, `supportsMaxOutputTokens`), `AnthropicMessagesCompat`
(`supportsEagerToolInputStreaming`, `supportsLongCacheRetention`, `sendSessionAffinityHeaders`, `sessionAffinityFormat`,
`supportsCacheControlOnTools`, `supportsTemperature`, `forceAdaptiveThinking`, `allowEmptySignature`, `supportsStrictTools`,
`supportsMidConvoEffort`, `supportsMidConvoSystemMessages`, `supportsMidConvoToolChanges`, `allowedFallbackModels`),
`BedrockCompat` (`supportsStrictMode`), `MistralConversationsCompat` (`supportsMidConvoSystemMessages`).

### 3.4 Thinking request shapes by `thinkingFormat` (VERIFIED `openai-completions.ts:875-972`)

`effort` below = `model.thinkingLevelMap[level] ?? level`; `off` = no level requested.

| Format | On | Off |
|---|---|---|
| `openai` | `reasoning_effort: effort` (if `supportsReasoningEffort`) | `reasoning_effort: map.off` only if it is a string (e.g. `"none"`) |
| `openrouter` | `reasoning: {effort}` | `reasoning: {effort: map.off ?? "none"}` unless `map.off === null` |
| `deepseek` | `thinking: {type:"enabled"}` + `reasoning_effort` if supported | `thinking: {type:"disabled"}` unless `map.off === null` |
| `zai` | `thinking: {type:"enabled", clear_thinking:false}` (+ `reasoning_effort`) | `thinking: {type:"disabled"}` |
| `qwen` | `enable_thinking: true` (+ `reasoning_effort`) | `enable_thinking: false` |
| `qwen-chat-template` | `chat_template_kwargs: {enable_thinking:true, preserve_thinking:true}` | `{enable_thinking:false, preserve_thinking:true}` |
| `chat-template` | `chat_template_kwargs` from `compat.chatTemplateKwargs` with `$var` substitution | same, `$var` resolves to off values |
| `baseten` | `chat_template_args` from `compat.chatTemplateArgs` + `reasoning_effort` | `reasoning_effort: map.off` |
| `together` | `reasoning: {enabled:true}` (+ `reasoning_effort`) | `reasoning: {enabled:false}` |
| `string-thinking` | `thinking: "<effort>"` | `thinking: map.off ?? "none"` unless null |
| `ant-ling` | `reasoning: {effort}` only if mapped to a string | nothing |

Budget field (independent of format): `{<thinkingTokenBudgetField>: budget}` where `budget = clamp(thinkingBudgetForLevel(level), answer room)`.
Default budgets (report 03): minimal 1024, low 2048, medium 8192, high 16384; at least 1024 answer tokens are kept.

### 3.5 Provider matrix (base URLs, env vars, auth, API, key quirks)

| gptr provider id | Base URL | Key env var(s) | Auth header | Wire API (Pi) | Must-handle quirks |
|---|---|---|---|---|---|
| `google` | `https://generativelanguage.googleapis.com/v1beta` | `GEMINI_API_KEY`, `GOOGLE_API_KEY` | `x-goog-api-key` | google-generative-ai | thought signatures, level vs budget, no `[DONE]` |
| `openrouter` | `https://openrouter.ai/api/v1` | `OPENROUTER_API_KEY` | `Authorization: Bearer` | openai-completions (+anthropic-messages) | `reasoning:{effort}`, `reasoning_details` replay, comment lines, mid-stream error chunk, `HTTP-Referer`/`X-OpenRouter-Title`, `x-session-id` |
| `groq` | `https://api.groq.com/openai/v1` | `GROQ_API_KEY` | Bearer | openai-completions | no `name`, `logprobs`, `logit_bias`; `n=1`; `delta.reasoning`; `reasoning_format`/`include_reasoning` |
| `cerebras` | `https://api.cerebras.ai/v1` | `CEREBRAS_API_KEY` | Bearer | openai-completions (non-standard) | no image URLs; `delta.reasoning`, replay `reasoning`; no `tool_stream` |
| `xai` | `https://api.x.ai/v1` | `XAI_API_KEY` | Bearer | openai-responses | completions lacks encrypted reasoning; no penalties/stop on reasoning models |
| `deepseek` | `https://api.deepseek.com` | `DEEPSEEK_API_KEY` | Bearer | openai-completions | `thinking:{type}`, `reasoning_content` replay required with tools (400), `max_tokens`, `prompt_cache_hit_tokens` |
| `mistral` | `https://api.mistral.ai` (+`/v1/chat/completions`) | `MISTRAL_API_KEY` | Bearer | mistral-conversations | 9-char alnum tool IDs; thinking as content chunks; `prompt_mode`; `x-affinity` |
| `together` | `https://api.together.ai/v1` | `TOGETHER_API_KEY` | Bearer | openai-completions | `reasoning:{enabled}`; field varies; R1 `<think>` in content; `max_tokens` |
| `fireworks` | `https://api.fireworks.ai/inference/v1` (Anthropic: `.../inference`) | `FIREWORKS_API_KEY` | Bearer | anthropic-messages / openai-completions | `accounts/fireworks/models/` IDs; session affinity |
| `huggingface` | `https://router.huggingface.co/v1` | `HF_TOKEN` | Bearer | openai-completions | no developer role; `:fastest`/`:cheapest`/`:preferred`/`:<provider>` suffixes |
| `nvidia` | `https://integrate.api.nvidia.com/v1` | `NVIDIA_API_KEY` | Bearer | openai-completions | `NVCF-POLL-SECONDS: 3600`; `max_tokens`; no effort/strict/store |
| `ollama` | `http://localhost:11434/v1` | none (dummy key) | Bearer (ignored) | openai-completions (custom) | base64 images only; no `tool_choice`; `reasoning` field; `max_tokens` |
| `ollama-cloud` | `https://ollama.com/v1` | `OLLAMA_API_KEY` | Bearer | openai-completions | no stateful Responses |
| `lmstudio` | `http://localhost:1234/v1` | `LMSTUDIO_API_KEY` (optional) | Bearer | openai-completions | also `/v1/responses` |
| `llamacpp` | `http://127.0.0.1:8080/v1` | `LLAMA_API_KEY` (+`LLAMA_BASE_URL`) | Bearer | openai-completions | `--jinja`; `reasoning_content`; `chat_template_kwargs`; `/health`, `/props`, `/models` |
| `vllm` | `http://localhost:8000/v1` | `VLLM_API_KEY` | Bearer | openai-completions | `reasoning` (renamed); `--reasoning-parser`; tool parser flags; `thinking_token_budget` |
| `azure` | `https://{resource}.openai.azure.com/openai/v1` | `AZURE_OPENAI_API_KEY` (+`_BASE_URL`/`_RESOURCE_NAME`/`_DEPLOYMENT_NAME_MAP`); models.dev: `AZURE_API_KEY`, `AZURE_RESOURCE_NAME` | `api-key` or Bearer (Entra) | azure-openai-responses | model = deployment |
| `amazon-bedrock` | `https://bedrock-runtime.{region}.amazonaws.com` | `AWS_BEARER_TOKEN_BEDROCK` or `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN`, `AWS_REGION`/`AWS_DEFAULT_REGION`, `AWS_PROFILE` | Bearer or SigV4 | bedrock-converse-stream | `/openai/v1/chat/completions` or `/model/{id}/converse-stream` (eventstream) |
| `github-copilot` | from token `proxy-ep` (default `https://api.individual.githubcopilot.com`) | `COPILOT_GITHUB_TOKEN` | Bearer (Copilot token) | mixed | editor headers; defer |
| `google` OpenAI layer | `https://generativelanguage.googleapis.com/v1beta/openai/` | `GEMINI_API_KEY` | Bearer | (not used by Pi) | `extra_body.google.thinking_config`; `tool_calls[].extra_content.google.thought_signature` |

Pi's default models per provider (`model-resolver.ts:20-62`) include: google `gemini-3.1-pro-preview`, groq `openai/gpt-oss-120b`,
cerebras `gpt-oss-120b`, deepseek `deepseek-v4-pro`, mistral `devstral-medium-latest`, xai `grok-4.7`, openrouter `moonshotai/kimi-k2.6`,
huggingface `moonshotai/Kimi-K2.6`, together `moonshotai/Kimi-K3`, fireworks `accounts/fireworks/models/kimi-k3`, azure (Pi id `azure-openai-responses`) `gpt-5.4`,
amazon-bedrock `us.anthropic.claude-opus-4-6-v1`, github-copilot `gpt-5.4`.

### 3.6 Bedrock specifics

OpenAI-compatible with an API key (from AWS docs, verbatim shape):
```bash
curl -X POST "https://bedrock-runtime.us-east-1.amazonaws.com/openai/v1/chat/completions" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"model": "openai.gpt-oss-120b-1:0", "messages": [{"role": "user", "content": "Hello"}]}'
```
The same request with SigV4: `curl --aws-sigv4 "aws:amz:us-east-1:bedrock" --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY"`.
Converse with an API key: `POST https://bedrock-runtime.us-east-1.amazonaws.com/model/us.anthropic.claude-sonnet-4-6/converse`,
body `{"messages":[{"role":"user","content":[{"text":"Hello"}]}]}`, `Authorization: Bearer $AWS_BEARER_TOKEN_BEDROCK`.

SigV4 algorithm (VERIFIED AWS IAM doc + test vectors): canonical request =
`METHOD\nCanonicalURI\nCanonicalQuery\nCanonicalHeaders\nSignedHeaders\nHex(SHA256(payload))`, where CanonicalHeaders are
`lowercase(name):trim(value)\n` sorted, SignedHeaders is the `;`-joined sorted names (must include `host`, `x-amz-date`,
`content-type` if present, `x-amz-security-token` for temporary credentials); string to sign =
`AWS4-HMAC-SHA256\n<YYYYMMDDTHHMMSSZ>\n<YYYYMMDD>/<region>/<service>/aws4_request\nHex(SHA256(canonical request))`;
key = `HMAC(HMAC(HMAC(HMAC("AWS4"+secret, date), region), service), "aws4_request")`; header
`Authorization: AWS4-HMAC-SHA256 Credential=<AK>/<scope>, SignedHeaders=<...>, Signature=<hex>`. Service name for Bedrock runtime: `bedrock`.
Canonical URI = URI-encode each path segment **as sent** (RFC 3986 unreserved `A-Za-z0-9-_.~` kept, uppercase hex).

Event-stream message layout: see 2.6; headers seen in ConverseStream: `:message-type` = `event`, `:event-type` ∈
{`messageStart`, `contentBlockStart`, `contentBlockDelta`, `contentBlockStop`, `messageStop`, `metadata`}, `:content-type` =
`application/json`; exceptions have `:message-type: exception` and `:exception-type` (e.g. throttling/validation) with a JSON
`{"message": ...}` payload. (Header names: VERIFIED Smithy spec; exact exception-type strings: LIKELY.)

### 3.7 GitHub Copilot headers
```
User-Agent: GitHubCopilotChat/0.35.0
Editor-Version: vscode/1.107.0
Editor-Plugin-Version: copilot-chat/0.35.0
Copilot-Integration-Id: vscode-chat
X-Initiator: user | agent            (agent when the last message is not a user message)
Openai-Intent: conversation-edits
Copilot-Vision-Request: true         (only when images are present)
```

### 3.8 models.dev JSON schema (VERIFIED by executing `SCR/analyze_modelsdev.R` on the 2026-09-29 download)

Top level: `{ "<provider_id>": Provider, ... }` (225 keys).

Provider:
```
id: string (225)          env: string[] (225)      npm: string (225, AI-SDK package = wire hint)
name: string (225)        doc: string URL (225)    api: string base URL (199; required for @ai-sdk/openai-compatible)
models: { "<model_id>": Model }
```
`npm` distribution: `@ai-sdk/openai-compatible` 184, `@ai-sdk/anthropic` 8, `@ai-sdk/openai` 6, `@ai-sdk/azure` 2,
`@openrouter/ai-sdk-provider` 2, then singletons (google, google-vertex, groq, cerebras, mistral, xai, togetherai, perplexity, cohere, deepinfra, amazon-bedrock, gateway, vercel, ...).

Model (counts out of 8,323; R class after `fromJSON(simplifyVector = FALSE)`):

| Field | Count | Type | Notes |
|---|---|---|---|
| `id`, `name`, `description` | 8323 | character | |
| `attachment` | 8323 | logical | file attachments |
| `reasoning` | 8323 | logical | |
| `tool_call` | 8323 | logical | |
| `open_weights` | 8323 | logical | |
| `release_date`, `last_updated` | 8323 | character | `YYYY-MM[-DD]` |
| `limit` | 8323 | list | `context` (8323), `output` (8323), `input` (1433) |
| `modalities` | 8323 | list | `input` ⊆ {text 8289, image 4904, pdf 2033, video 1409, audio 758}; `output` ⊆ {text 8115, image 200, audio 83, video 67, pdf 2} |
| `cost` | 7902 | list | `input`, `output` (7902), `cache_read` (5359), `cache_write` (1767), `tiers` (606), `context_over_200k` (511), `reasoning` (152), `input_audio` (135), `output_audio` (18); USD / 1M tokens |
| `temperature` | 7789 | logical | NULL for 534 |
| `family` | 7627 | character | |
| `reasoning_options` | 6134 | list | items `{type:"effort", values:[...]}` 3813, `{type:"toggle"}` 1377, `{type:"budget_tokens", min?, max?}` 598; may be empty `[]` |
| `structured_output` | 5816 | logical | |
| `canonical_model_id` | 5257 | character | `owner/id` |
| `knowledge` | 4325 | character | cutoff |
| `interleaved` | 1217 | logical (103) or list `{field}` (1114: `reasoning_content` 1099, `reasoning_details` 15) | |
| `provider` | 339 | list | `npm` 333, `api` 174, `shape` 44 (`responses` 36, `completions` 8) |
| `status` | 324 | character | `beta` 72, `deprecated` 252 (`alpha` allowed by schema) |
| `experimental` | 55 | list | `modes.<name>.{cost, provider{body, headers}}` |
| `type` | (decision endpoint) | character | `"decision"` for System-1 models (models.json?type=decision) |

Sample entries (verbatim, executed `analyze4.R`):
```json
{"id":"gemini-3.5-flash","name":"Gemini 3.5 Flash","description":"Fast Gemini model balancing multimodal reasoning, tool use, and cost",
 "family":"gemini-flash","attachment":true,"reasoning":true,
 "reasoning_options":[{"type":"effort","values":["minimal","low","medium","high"]}],
 "tool_call":true,"structured_output":true,"temperature":true,"knowledge":"2025-01",
 "release_date":"2026-05-19","last_updated":"2026-05-19",
 "modalities":{"input":["text","image","video","audio","pdf"],"output":["text"]},"open_weights":false,
 "limit":{"context":1048576,"output":65536},"cost":{"input":1.5,"output":9,"cache_read":0.15,"input_audio":1.5}}
```
```json
{"id":"deepseek-v4-flash-vision-exp", ..., "reasoning_options":[{"type":"toggle"},{"type":"effort","values":["low","high","max"]}],
 "tool_call":true,"interleaved":{"field":"reasoning_content"}, ..., "status":"deprecated",
 "cost":{"input":0.15,"output":0.6,"reasoning":0.6,"cache_read":0.003},"canonical_model_id":"deepseek/deepseek-v4.1-flash"}
```
```json
"cost":{"input":2.5,"output":7.5,"cache_read":0.5,"tiers":[{"input":5,"output":15,"cache_read":1,"tier":{"type":"context","size":32000}},
                                                        {"input":6.25,"output":18.5,"cache_read":1.25,"tier":{"type":"context","size":128000}}]}
```
```json
"experimental":{"modes":{"fast":{"cost":{"input":8,"output":40,"cache_read":0.4,"cache_write":10},
  "provider":{"body":{"speed":"fast"},"headers":{"anthropic-beta":"fast-mode-2026-02-01"}}}}}
```
Provider objects: `{"id":"google","env":["GOOGLE_API_KEY","GOOGLE_GENERATIVE_AI_API_KEY","GEMINI_API_KEY"],"npm":"@ai-sdk/google","name":"Google","doc":"https://ai.google.dev/gemini-api/docs/models"}`;
`{"id":"deepseek","env":["DEEPSEEK_API_KEY"],"npm":"@ai-sdk/openai-compatible","api":"https://api.deepseek.com","name":"DeepSeek","doc":"..."}`.

Provider IDs relevant to gptr and their env/base (executed `analyze2.R`): google (39 models), google-vertex (54), openai (53),
anthropic (16), groq (16), cerebras (2), xai (12), deepseek (4; api `https://api.deepseek.com`), mistral (34), togetherai (36),
fireworks-ai (22; api `https://api.fireworks.ai/inference/v1/`), huggingface (78; `https://router.huggingface.co/v1`), openrouter
(387; `https://openrouter.ai/api/v1`), ollama-cloud (24; `https://ollama.com/v1`), lmstudio (3; `http://127.0.0.1:1234/v1`),
llama (Meta, `https://api.llama.com/compat/v1/`), azure (94), azure-cognitive-services (86), amazon-bedrock (182; env
`AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_BEARER_TOKEN_BEDROCK`), github-copilot (34; `GITHUB_TOKEN`,
`https://api.githubcopilot.com`), vercel (394), nvidia (103). **No local `ollama` provider** and no `typesafe` provider exist in api.json.

### 3.9 Thinking levels

Vocabulary: `off < minimal < low < medium < high < xhigh < max`. A model's supported set: `off` only if `!reasoning`; otherwise
all levels whose map value is not `null`, with `xhigh`/`max` present only if explicitly mapped (`models.ts:1217-1226`).
Clamp: if unsupported, walk **up** to the next supported level, else **down** (`:1228-1249`). Map from models.dev effort values:
`off ← "none"` (else `null`), each level to itself if listed, else `null`.

---

## 4. Recommended design for gptr

### 4.1 Architecture

Keep Pi's split: a small set of **wire adapters** ("apis"), plus **providers** (base URL, auth, default compat, model list),
plus **models** (catalog entries). For this track:

| api id | Used by | Status |
|---|---|---|
| `openai-completions` | OpenRouter, Groq, Cerebras, DeepSeek, Together, Fireworks(OA), HF, NVIDIA, Mistral (profile), Ollama, LM Studio, llama.cpp, vLLM, Azure (chat), Bedrock (OpenAI path), any custom endpoint | phase 1 |
| `gemini` (generateContent) | Google AI Studio keys; later Vertex (same body, different URL/auth) | phase 1 |
| `openai-responses` | OpenAI, xAI, Azure (responses) — owned by the OpenAI track | phase 1 (other track) |
| `anthropic-messages` | Anthropic, OpenRouter anthropic/*, Fireworks, llama.cpp | other track |
| `bedrock-converse` | Bedrock Converse/ConverseStream (eventstream + SigV4) | phase 2 |
| `gemini-interactions` | Gemini Interactions API | phase 3 (when a feature needs it) |

### 4.2 Data structures (plain R lists with S3 class tags; no R6 needed)

```r
# a provider
list(id = "groq", name = "Groq", api = "openai-completions",
     base_url = "https://api.groq.com/openai/v1",
     key_env = c("GROQ_API_KEY"),               # first non-empty wins; .env aliases handled by the auth track
     auth = "bearer",                            # "bearer" | "x-goog-api-key" | "api-key" | "sigv4" | "none"
     headers = list(),                           # static headers
     compat = list(),                            # provider-level compat overrides
     local = FALSE, discover = NULL)             # local servers: discover = function() -> models via /v1/models
# a model (class "gptr_model")
list(provider = "groq", id = "openai/gpt-oss-120b", name = "...", api = "openai-completions",
     base_url = NULL,                           # NULL = provider's
     reasoning = TRUE, thinking_map = list(off = NULL, minimal = "low", ...),  # NA = unsupported
     input = c("text", "image"), context = 131072, max_output = 32768,
     cost = list(input = 0.15, output = 0.6, cache_read = 0, cache_write = 0, tiers = NULL),
     interleaved_field = NULL,                  # e.g. "reasoning_content" from models.dev
     compat = list(), headers = list(), sampling = list(),
     owner = "openai", family = "gpt-oss", status = "", source = "snapshot")  # snapshot|cache|user|live
```
`compat_openai_defaults()` returns the full flag list with Pi's defaults; `compat_detect(provider, base_url, model_id)` ports
`detectCompat()` (3.3) exactly; `compat_resolve(model) = modifyList(modifyList(detect, provider$compat), model$compat)`.

### 4.3 Function surface (proposed names/signatures)

```r
# ---- catalog ---------------------------------------------------------------
gptr_models(provider = NULL, type = c("chat", "decision"), refresh = FALSE)   # data.frame view of the merged catalog
gptr_models_update(url = "https://models.dev/api.json", quiet = FALSE)        # explicit refresh -> R_user_dir cache (ETag)
gptr_models_reset()                                                            # delete cache, back to shipped snapshot
gptr_model(ref, ...)                    # resolve a reference (string or NSE) -> gptr_model; ... overrides fields
gptr_register_provider(id, base_url, api = "openai-completions", key_env = NULL, auth = "bearer",
                       headers = list(), compat = list(), models = NULL)       # custom/local endpoints, session-scoped
gptr_register_model(provider, id, ...)                                         # add/override one model
gptr_discover(provider = c("ollama", "lmstudio", "llamacpp", "vllm"), base_url = NULL, timeout = 1)  # GET /v1/models

# ---- low-level streaming (internal, exported for extension authors) --------
stream_chat(model, context, options = list(), on_event = NULL)   # dispatches on model$api; returns assistant message
sse_parser()                                                      # byte-level SSE decoder (5.1)
es_decoder()                                                      # AWS eventstream decoder (5.4)
aws_sigv4_sign(method, url, headers, body, access_key, secret_key, session_token = NULL, region, service, time = Sys.time())
```

### 4.4 Transport (all adapters)

- Default: **curl multi interface** (`curl::new_pool()`, `multi_add(data=)`, `multi_run(timeout = 0.05, poll = TRUE)` loop). This
  keeps R responsive to interrupts (`tryCatch(interrupt=)` → `multi_cancel()`), streams at true latency, supports several
  parallel streams (sub-agents) in one R process (report 03 5.4 showed 3 interleaved streams), and needs only `curl`.
- httr2 may be used for non-streaming calls (retries, `req_error`), but **never `resp_stream_sse()` on a blocking connection**.
  If httr2 is used for streaming: `req_perform_connection(blocking = FALSE)` + `resp_stream_raw()` + our own `sse_parser()`.
- Timeouts: `connecttimeout = 10`, idle timeout via `low_speed_time = <idle s>`, `low_speed_limit = 1`; **no total timeout**
  (long generations). Add an app-level idle watchdog.
- Parse SSE on raw bytes; split only on 0x0A/0x0D; `Encoding(x) <- "UTF-8"` on decoded strings; ignore `:` comment lines;
  accept LF/CRLF/CR; flush a final unterminated event at EOF (lenient).
- HTTP errors (≥400): buffer the body, extract `error.message` (OpenAI/Google shape) or `message`, and signal a classed condition
  `gptr_http_error` with `status` and `body`; the retry policy is owned by the providers track (429/5xx with `retry-after`).

### 4.5 Gemini adapter algorithm (port of Pi, REST)

Request (`gemini_build_body(model, context, options)`):
1. `systemInstruction = {parts:[{text: <collapsed system prompt>}]}` if non-empty.
2. For each message: user → `{role:"user", parts:[{text}|{inlineData:{mimeType,data}}]}`; assistant from the **same provider+model** →
   `{role:"model", parts:[...]}` keeping `thought:true` parts and `thoughtSignature`s exactly on the parts they came on
   (drop empty parts unless signed); assistant from another model → thinking as plain text, no signatures; tool calls →
   `{functionCall:{name, args, id (if Gemini>=3)}, thoughtSignature?}`; tool results → `functionResponse{name, id?, response:{output|error}, parts? (Gemini>=3 images)}`,
   merging consecutive results into one user turn; for Gemini < 3 add a separate user image turn.
3. Tool IDs normalised to `[A-Za-z0-9_-]{1,64}` when required.
4. `tools = [{functionDeclarations:[{name, description, parametersJsonSchema}]}]`; `toolConfig.functionCallingConfig.mode`: an explicit
   `tool_choice` of `none`/`any` wins (Pi `resolveGoogleFunctionCallingMode`, `google-shared.ts:423-436`), otherwise `VALIDATED`
   if strict tools on Gemini>=3, otherwise from `tool_choice` (`auto`→`AUTO`; gptr may also map `required`→`ANY`, which Pi does not:
   Pi maps unknown choices to `AUTO`), + `allowedFunctionNames`.
5. `generationConfig`: `maxOutputTokens`, `temperature`; thinking: level-model → `{includeThoughts:TRUE, thinkingLevel: toupper(level)}`
   (clamped with the model's map, so `minimal` on 3.8 Flash becomes `low`); budget-model → `{includeThoughts:TRUE, thinkingBudget}`;
   off → `thinkingBudget: 0` or the lowest supported level.
Stream: use the accumulator in 5.1 (`gemini_accumulator_new`), which is verified: thinking vs text blocks by `thought`,
signatures retained per block, complete function calls, usage normalisation, stop mapping (3.1).

### 4.6 OpenAI-compatible adapter algorithm

Port 2.3 literally, parameterised by the resolved compat list. Additional gptr rules beyond Pi:
- **`interleaved_field` from models.dev**: when set, always replay assistant reasoning in that field (covers DeepSeek, Kimi, and others automatically).
- **Mistral profile** (`compat$tool_id = "alnum9"`, `compat$thinking_in_content_array = TRUE`): hash tool IDs to 9 alphanumeric
  characters; parse `delta.content` arrays with `{type:"thinking"}` items; `prompt_mode:"reasoning"` or `reasoning_effort`.
- **`<think>` splitter** (`compat$think_tags = TRUE`): a streaming state machine that routes text between `<think>` and `</think>` to
  thinking deltas (needed for Together DeepSeek-R1, Groq `raw`, llama.cpp `--reasoning-format none`). Handle tags split across chunks.
- **Groq**: never send `name` on messages. That is already the default because `requiresToolResultName = FALSE`, and gptr should also
  never add a `name` to user messages.
- **Images**: always send base64 data URLs (Ollama and Cerebras reject external URLs).
- **Azure**: `auth = "api-key"` header; `model = deployment` (map via `AZURE_OPENAI_DEPLOYMENT_NAME_MAP`); base URL normalisation as Pi.
- **OpenRouter**: add `HTTP-Referer: https://cran.r-project.org/package=gptr` and `X-OpenRouter-Title: gptr` (configurable/opt-out);
  treat `finish_reason:"error"` + `error` as a terminal error that keeps partial text.

Local provider default compat (from Pi's llama.cpp profile): `supportsStore=FALSE, supportsDeveloperRole=FALSE,
supportsReasoningEffort=FALSE (TRUE for ollama/vllm), supportsUsageInStreaming=TRUE, supportsStrictMode=FALSE, maxTokensField="max_tokens"`.
Discovery: `GET {base}/v1/models` (all four servers), llama.cpp extras `GET /props` (`chat_template` contains `enable_thinking` →
`thinkingFormat = "qwen-chat-template"`; `meta.n_ctx` → context), Ollama extras `POST /api/show` for context/capabilities (optional).
Health probe with a 1 s timeout; never probe during `R CMD check` (4.10).

### 4.7 Bedrock plan

- Phase 1 (no new deps): provider `amazon-bedrock` with `api = "openai-completions"`,
  `base_url = sprintf("https://bedrock-runtime.%s.amazonaws.com/openai/v1", region)`, `auth = "bearer"` from `AWS_BEARER_TOKEN_BEDROCK`.
  Only models whose card lists Chat Completions work (OpenAI gpt-oss, others per AWS tables).
- Phase 2: `bedrock-converse` adapter: JSON body per 2.6, response via `es_decoder()`; auth = Bearer if the token is set, else
  SigV4 from `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` (pure R `aws_sigv4_sign()`, or libcurl `aws_sigv4` when
  available and no session token is needed). Region from `AWS_REGION` → `AWS_DEFAULT_REGION` → ARN → `us-east-1`.
  `~/.aws` profiles/SSO/IMDS: delegate to `paws.common` if installed (Suggests); otherwise say so in the error.

### 4.8 Catalog strategy (CRAN-compatible)

1. **Build time (maintainer script `data-raw/models.R`, not run on CRAN)**: download `api.json` and `models.json?type=decision`,
   prune to the supported providers, keep tool-capable, non-deprecated, text-output models, keep the fields in 3.8 (drop
   `description`, `experimental` optional), write `inst/extdata/models-dev.json.gz` with `_meta = {source, license, fetched, etag}`.
   Measured: 25 providers / 1,227 models → 51.3 KB gz (34.2 KB xz, 44.8 KB rds-xz); load 0.05 s. Apply gptr's own
   corrections in a separate, reviewed `inst/extdata/model-overrides.json` (like Pi's hand-maintained lists), not by editing the snapshot.
2. **Run time**: lazily load the snapshot on first use into a package-level environment (`.gptr$catalog`).
3. **Refresh only on explicit request**: `gptr_models_update()` performs a conditional GET with the stored ETag (304 → touch only),
   validates the JSON (top-level object of providers with `models`), writes atomically (`tempfile()` in the same dir + `file.rename()`)
   to `file.path(tools::R_user_dir("gptr", "cache"), "models-dev.json.gz")`, and prunes old files. No automatic background
   network access, and nothing written at load time.
4. **Merge order** (later wins, per `provider/id`): shipped snapshot < user cache (if newer `fetched`) < gptr overrides <
   user config (`gptr_register_*()` / config file) < live discovery (local servers).
5. **User-defined models config**: a YAML or JSON file at `file.path(tools::R_user_dir("gptr","config"), "models.json")` and/or
   `.gptr/models.json` in the workspace (REQ-27), schema mirroring Pi's `models.json` (`PI/coding-agent/src/core/model-config.ts:185-253`):
   ```json
   {"providers": {"ollama": {"baseUrl": "http://localhost:11434/v1", "api": "openai-completions", "apiKey": "ollama",
      "compat": {"supportsDeveloperRole": false},
      "models": [{"id": "qwen2.5-coder:7b", "reasoning": false, "input": ["text"], "contextWindow": 32768, "maxTokens": 8192}]},
     "anthropic": {"modelOverrides": {"claude-sonnet-5-5": {"maxTokens": 64000}}}}}
   ```
   Support `$NAME`/`${NAME}` env interpolation in `apiKey`/headers (Pi `custom-provider.md:76-81`); treat `!command` as opt-in
   only (security). Never store literal keys in scripts or histories.

### 4.9 Model reference syntax for gptr

Grammar (strings):
```
ref      := [provider "/"] model_id [":" thinking]  |  alias [":" thinking]  |  family [":" thinking]
thinking := "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max"
```
Examples: `"anthropic/claude-sonnet-5-5"`, `"openai/gpt-6-sol:high"`, `"google/gemini-3.8-flash:low"`, `"ollama/llama3.2:3b"`,
`"ollama/qwen3.5:9b:high"`, `"openrouter/anthropic/claude-sonnet-5.5"`, `"huggingface/openai/gpt-oss-120b:cheapest"`, `"sonnet"`,
`"opus:xhigh"`, `"jev"`, `"claude-sonnet"`.

NSE (REQ-19), in `gptr(..., model = )` and similar identifier arguments:
1. `substitute(model)`; if it is a symbol bound in the caller to a character(1) or `gptr_model`, use the value (variables win).
2. Otherwise a symbol → its name (`sonnet`, `jev`); a call built only from `/`, `-`, `:`, `::`, symbols and numbers → deparse and
   strip whitespace. Any other call → error "quote the model reference".
3. If the call contains a non-integer number, check for trailing-zero variants in the catalog (`5.1` → `5.10`, `5.100`); if one exists,
   error with "did you mean"; otherwise accept but always `message()` the resolved canonical reference.
4. Parse errors (IDs with tokens like `120b`, `31b`) cannot be intercepted; document "quote IDs that start with digits after a separator".

Resolution algorithm (implemented and verified in 5.5): exact `provider/id` → known provider prefix + recursive match within it →
exact bare ID → `.`/`-`/`_`-normalised ID → tie-break (single authenticated provider, then the owner from `canonical_model_id`) →
alias table → family (newest non-deprecated, owner preferred) → substring (Pi's alias-over-dated rule). Then, only if nothing
matched, the last-colon thinking suffix is peeled and the match retried. Failures return the reason plus three `adist()` suggestions;
an unknown ID under a known provider can become a fallback model (Pi's behaviour) behind `allow_unknown = TRUE` (default TRUE
for local providers, FALSE for hosted ones, so typos are not sent as billable requests).

Aliases (dynamic, resolved against the catalog at call time so they never go stale):
`sonnet` → newest `anthropic` family `claude-sonnet`; `opus` → `claude-opus`; `haiku` → `claude-haiku`; `gemini`/`flash` →
`google/gemini-flash-latest`; `gpt` → newest `openai` `gpt-*-sol`; `jev` → `typesafe/jev-latest` (System 1). Users can add aliases
(`options(gptr.aliases = list(fast = "groq/openai/gpt-oss-120b"))` or the config file). In the session script (REQ-24) always write the
fully resolved quoted reference, e.g. `gptr("...", model = "anthropic/claude-sonnet-5-5:high")`, so replays are stable even when
aliases move.

### 4.10 Package choices

| Package | Role | Imports / Suggests |
|---|---|---|
| curl (≥ 5.0) | all HTTP incl. streaming (multi), optional `aws_sigv4` | **Imports** |
| jsonlite | JSON | **Imports** |
| openssl | SigV4 HMAC/SHA-256 (also base64/PKCE for other tracks) | **Imports** (tiny SigV4 cost) |
| httr2 | convenience for non-streaming requests/retries | Suggests or Imports (choose one HTTP stack; curl alone suffices) |
| digest | faster CRC32 for eventstream | Suggests (pure-R fallback verified) |
| processx / callr, httpuv | tests only: mock servers | Suggests |
| paws.common / aws.signature | AWS profile/SSO credential chains | Suggests |
| yaml | YAML config (if chosen over JSON) | Suggests |

---

## 5. Verified R prototypes

All code below was run with `Rscript --vanilla` on this machine, locale `C`. Files are in `SCR/v2/`.

### 5.1 Generic OpenAI-compatible + Gemini streaming client against a local mock server

`SCR/v2/stream_client.R` (complete):
```r
# Prototype streaming client for gptr: OpenAI-compatible Chat Completions and
# Gemini streamGenerateContent (alt=sse), three interchangeable transports.
`%||%` <- function(x, y) if (is.null(x)) y else x
now <- function() proc.time()[["elapsed"]]

# ---------------------------------------------------------------------------
# 1. Byte-level SSE parser. Splits only on 0x0A / 0x0D, which never occur inside
#    a UTF-8 multi-byte sequence, so characters cut across TCP chunks are safe.
#    Accepts LF, CRLF and CR line endings; ignores ':' comment lines.
# ---------------------------------------------------------------------------
sse_parser_new <- function() {
  buf <- raw(0)
  boundary <- function(b) {
    n <- length(b); if (n < 2L) return(NULL)
    for (p in which(b == as.raw(10L) | b == as.raw(13L))) {
      if (p + 1L <= n && b[p] == as.raw(10L) && b[p + 1L] == as.raw(10L)) return(c(p - 1L, p + 1L))
      if (p + 3L <= n && b[p] == as.raw(13L) && b[p + 1L] == as.raw(10L) &&
          b[p + 2L] == as.raw(13L) && b[p + 3L] == as.raw(10L)) return(c(p - 1L, p + 3L))
      if (p + 1L <= n && b[p] == as.raw(13L) && b[p + 1L] == as.raw(13L)) return(c(p - 1L, p + 1L))
    }
    NULL
  }
  parse_event <- function(bytes) {
    txt <- rawToChar(bytes); Encoding(txt) <- "UTF-8"
    ev <- list(event = "message", data = character(0), id = NULL)
    for (ln in strsplit(txt, "\r\n|\n|\r")[[1]]) {
      if (!nzchar(ln) || startsWith(ln, ":")) next
      c1 <- regexpr(":", ln, fixed = TRUE)
      field <- if (c1 < 0) ln else substr(ln, 1L, c1 - 1L)
      value <- if (c1 < 0) "" else sub("^ ", "", substr(ln, c1 + 1L, nchar(ln)))
      if (field == "data") ev$data <- c(ev$data, value)
      else if (field == "event") ev$event <- value
      else if (field == "id") ev$id <- value
    }
    if (!length(ev$data)) return(NULL)
    ev$data <- paste(ev$data, collapse = "\n"); ev
  }
  feed <- function(chunk) {
    buf <<- c(buf, chunk); out <- list()
    repeat {
      bd <- boundary(buf); if (is.null(bd)) break
      ev <- if (bd[1] >= 1L) parse_event(buf[seq_len(bd[1])]) else NULL
      buf <<- if (bd[2] < length(buf)) buf[(bd[2] + 1L):length(buf)] else raw(0)
      if (!is.null(ev)) out[[length(out) + 1L]] <- ev
    }
    out
  }
  # At EOF a final event without the blank line is dispatched (lenient; the
  # WHATWG spec would discard it).
  flush <- function() { if (!length(buf)) return(list()); ev <- parse_event(buf); buf <<- raw(0); if (is.null(ev)) list() else list(ev) }
  list(feed = feed, flush = flush)
}

# ---------------------------------------------------------------------------
# 2a. OpenAI Chat Completions chunk accumulator (quirks from Pi openai-completions.ts)
# ---------------------------------------------------------------------------
oai_accumulator_new <- function(on_event = NULL, supports_finish_reason = TRUE) {
  st <- new.env(parent = emptyenv())
  st$text <- ""; st$thinking <- ""; st$thinking_field <- NULL; st$tools <- list()
  st$finish <- NULL; st$usage <- NULL; st$id <- NULL; st$model <- NULL; st$error <- NULL; st$done <- FALSE
  emit <- function(type, ...) if (is.function(on_event)) on_event(list(type = type, ...))
  push_sse <- function(ev) {
    if (identical(ev$data, "[DONE]")) { st$done <- TRUE; return(TRUE) }
    ch <- tryCatch(jsonlite::fromJSON(ev$data, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(ch)) return(FALSE)
    if (!is.null(ch$error)) st$error <- ch$error$message %||% "provider error"   # mid-stream error object
    st$id <- st$id %||% ch$id; st$model <- st$model %||% ch$model
    if (!is.null(ch$usage)) st$usage <- ch$usage
    c0 <- if (length(ch$choices)) ch$choices[[1]] else NULL
    if (is.null(c0)) return(FALSE)
    if (is.null(ch$usage) && !is.null(c0$usage)) st$usage <- c0$usage              # Moonshot
    if (!is.null(c0$finish_reason)) st$finish <- c0$finish_reason
    dl <- c0$delta; if (is.null(dl)) return(FALSE)
    if (is.character(dl$content) && nzchar(dl$content)) { st$text <- paste0(st$text, dl$content); emit("text_delta", delta = dl$content) }
    for (f in c("reasoning_content", "reasoning", "reasoning_text")) {   # first non-empty only (chutes duplicates)
      v <- dl[[f]]
      if (is.character(v) && nzchar(v)) { st$thinking <- paste0(st$thinking, v); st$thinking_field <- st$thinking_field %||% f
                                          emit("thinking_delta", delta = v); break }
    }
    for (t in dl$tool_calls) {
      key <- as.character(t$index %||% length(st$tools))
      cur <- st$tools[[key]] %||% list(id = "", name = "", arguments = "")
      if (is.character(t$id) && nzchar(t$id)) cur$id <- t$id
      fn <- t[["function"]]
      if (is.character(fn$name) && nzchar(fn$name) && !nzchar(cur$name)) cur$name <- fn$name
      if (is.character(fn$arguments) && nzchar(fn$arguments)) { cur$arguments <- paste0(cur$arguments, fn$arguments)
                                                                emit("toolcall_delta", index = key, delta = fn$arguments) }
      st$tools[[key]] <- cur
    }
    FALSE
  }
  result <- function() {
    tools <- lapply(unname(st$tools), function(t) list(id = t$id, name = t$name,
      arguments = tryCatch(jsonlite::fromJSON(if (nzchar(t$arguments)) t$arguments else "{}", simplifyVector = FALSE),
                           error = function(e) structure(list(), parse_error = conditionMessage(e)))))
    fr <- st$finish
    stop_reason <- if (!is.null(st$error)) "error"
      else if (is.null(fr)) { if (supports_finish_reason) "error" else if (length(tools)) "tool_use" else "stop" }
      else switch(fr, stop = , end = "stop", length = "length", tool_calls = , function_call = "tool_use", "error")
    u <- st$usage
    cached <- u$prompt_tokens_details$cached_tokens %||% u$prompt_cache_hit_tokens %||% u$cached_tokens %||% 0
    cw <- u$prompt_tokens_details$cache_write_tokens %||% 0
    list(text = st$text, thinking = st$thinking, thinking_field = st$thinking_field, tool_calls = tools,
         stop_reason = stop_reason, raw_finish = fr, error = st$error, got_done_sentinel = st$done,
         usage = list(input = max(0, (u$prompt_tokens %||% 0) - cached - cw), output = u$completion_tokens %||% 0,
                      cache_read = cached, cache_write = cw,
                      reasoning = u$completion_tokens_details$reasoning_tokens %||% 0),
         response_id = st$id, response_model = st$model)
  }
  list(push_sse = push_sse, result = result)
}

# ---------------------------------------------------------------------------
# 2b. Gemini streamGenerateContent chunk accumulator (rules from Pi google-shared.ts)
#     No [DONE] sentinel: the stream ends when the HTTP body ends.
# ---------------------------------------------------------------------------
gemini_accumulator_new <- function(on_event = NULL) {
  st <- new.env(parent = emptyenv())
  st$blocks <- list(); st$finish <- NULL; st$usage <- NULL; st$id <- NULL; st$model_version <- NULL
  emit <- function(type, ...) if (is.function(on_event)) on_event(list(type = type, ...))
  last_type <- function() if (length(st$blocks)) st$blocks[[length(st$blocks)]]$type else ""
  push_sse <- function(ev) {
    ch <- tryCatch(jsonlite::fromJSON(ev$data, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(ch)) return(FALSE)
    st$id <- st$id %||% ch$responseId; st$model_version <- st$model_version %||% ch$modelVersion
    cand <- if (length(ch$candidates)) ch$candidates[[1]] else NULL
    for (p in cand$content$parts) {
      if (!is.null(p$text)) {
        type <- if (isTRUE(p$thought)) "thinking" else "text"
        if (last_type() != type) st$blocks[[length(st$blocks) + 1L]] <- list(type = type, text = "", signature = NULL)
        k <- length(st$blocks)
        st$blocks[[k]]$text <- paste0(st$blocks[[k]]$text, p$text)
        if (is.character(p$thoughtSignature) && nzchar(p$thoughtSignature)) st$blocks[[k]]$signature <- p$thoughtSignature  # retain last non-empty
        emit(paste0(type, "_delta"), delta = p$text)
      }
      if (!is.null(p$functionCall)) {
        fc <- p$functionCall
        st$blocks[[length(st$blocks) + 1L]] <- list(type = "tool_call",
          id = fc$id %||% sprintf("%s_%d", fc$name, length(st$blocks)), name = fc$name,
          arguments = fc$args %||% structure(list(), names = character(0)),
          signature = p$thoughtSignature)       # only the FIRST parallel call carries one; keep per part
        emit("toolcall", name = fc$name)
      }
    }
    if (!is.null(cand$finishReason)) st$finish <- cand$finishReason
    if (!is.null(ch$usageMetadata)) st$usage <- ch$usageMetadata
    FALSE
  }
  result <- function() {
    fr <- st$finish
    has_tool <- any(vapply(st$blocks, function(b) b$type == "tool_call", TRUE))
    stop_reason <- if (is.null(fr)) "error" else switch(fr, STOP = if (has_tool) "tool_use" else "stop",
                                                        MAX_TOKENS = "length", "error")
    u <- st$usage
    list(blocks = st$blocks, stop_reason = stop_reason, raw_finish = fr, response_id = st$id,
         model_version = st$model_version,
         usage = list(input = (u$promptTokenCount %||% 0) - (u$cachedContentTokenCount %||% 0),
                      output = (u$candidatesTokenCount %||% 0) + (u$thoughtsTokenCount %||% 0),
                      cache_read = u$cachedContentTokenCount %||% 0, cache_write = 0,
                      reasoning = u$thoughtsTokenCount %||% 0, total = u$totalTokenCount %||% 0))
  }
  list(push_sse = push_sse, result = result)
}

# ---------------------------------------------------------------------------
# 3. Transports. Each calls on_sse(ev) for every parsed SSE event; on_sse
#    returns TRUE to stop early. They return list(status, headers, error_body, stamps).
# ---------------------------------------------------------------------------
http_error_message <- function(status, txt) {
  msg <- tryCatch({ b <- jsonlite::fromJSON(txt, simplifyVector = FALSE); b$error$message %||% b$message %||% txt },
                  error = function(e) txt)
  structure(class = c("gptr_http_error", "error", "condition"),
            list(message = sprintf("HTTP %d: %s", status, msg), call = NULL, status = status, body = txt))
}

# (a) curl multi interface: the R loop regains control every `poll` seconds
transport_curl <- function(url, headers, body_json, on_sse, timeout = 60, poll = 0.05) {
  payload <- charToRaw(enc2utf8(body_json))
  h <- curl::new_handle(url = url, post = TRUE, postfieldsize = length(payload), postfields = payload,
                        connecttimeout = 10, low_speed_time = timeout, low_speed_limit = 1L)
  do.call(curl::handle_setheaders, c(list(h), headers))
  parser <- sse_parser_new(); st <- new.env(parent = emptyenv())
  st$done <- FALSE; st$fail <- NULL; st$stop <- FALSE; st$status <- NULL; st$err <- raw(0); st$stamps <- numeric(0)
  pool <- curl::new_pool()
  curl::multi_add(h, pool = pool,
    data = function(x, final = FALSE) {
      if (is.null(st$status)) st$status <- curl::handle_data(h)$status_code
      if (st$status >= 400L) { st$err <- c(st$err, x); return(invisible()) }
      if (st$stop) return(invisible())
      for (ev in parser$feed(x)) { st$stamps <- c(st$stamps, now()); if (isTRUE(on_sse(ev))) { st$stop <- TRUE; break } }
    },
    done = function(res) { st$done <- TRUE; st$status <- res$status_code; st$headers <- res$headers },
    fail = function(msg) { st$done <- TRUE; st$fail <- msg })
  tryCatch(while (!st$done && !st$stop) curl::multi_run(timeout = poll, poll = TRUE, pool = pool),
           interrupt = function(e) { curl::multi_cancel(h); stop("aborted by user", call. = FALSE) })
  if (st$stop && !st$done) curl::multi_cancel(h)
  if (!is.null(st$fail)) stop("transport error: ", st$fail, call. = FALSE)
  if (!st$stop && (st$status %||% 0) < 400L) for (ev in parser$flush()) on_sse(ev)
  if (st$status >= 400L) stop(http_error_message(st$status, rawToChar(st$err)))
  list(status = st$status, headers = curl::parse_headers_list(st$headers %||% raw(0)), stamps = st$stamps)
}

# (b) httr2 non-blocking connection + polling (interruptible, no busy wait)
transport_httr2_poll <- function(url, headers, body_json, on_sse, timeout = 60) {
  req <- httr2::request(url) |>
    httr2::req_headers(!!!headers, .redact = c("Authorization", "x-goog-api-key", "api-key")) |>
    httr2::req_body_raw(body_json, type = "application/json") |>
    httr2::req_options(connecttimeout = 10, low_speed_time = timeout, low_speed_limit = 1L) |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- httr2::req_perform_connection(req, blocking = FALSE)
  on.exit(close(resp), add = TRUE)
  status <- httr2::resp_status(resp)
  parser <- sse_parser_new(); stamps <- numeric(0); errbuf <- raw(0)
  repeat {
    chunk <- httr2::resp_stream_raw(resp, kb = 64)
    if (length(chunk)) {
      if (status >= 400L) { errbuf <- c(errbuf, chunk); next }
      stop_now <- FALSE
      for (ev in parser$feed(chunk)) { stamps <- c(stamps, now()); if (isTRUE(on_sse(ev))) { stop_now <- TRUE; break } }
      if (stop_now) break
    } else if (httr2::resp_stream_is_complete(resp)) {
      break
    } else Sys.sleep(0.01)    # interrupt window; later::later_fd() would avoid the sleep
  }
  if (status >= 400L) stop(http_error_message(status, rawToChar(errbuf)))
  for (ev in parser$flush()) on_sse(ev)
  list(status = status, headers = as.list(httr2::resp_headers(resp)), stamps = stamps)
}

# (c) httr2 blocking connection + httr2::resp_stream_sse (what ellmer 0.4.0 does
#     for synchronous streaming) - kept to measure its latency behaviour
transport_httr2_sse_blocking <- function(url, headers, body_json, on_sse, timeout = 60) {
  req <- httr2::request(url) |> httr2::req_headers(!!!headers) |>
    httr2::req_body_raw(body_json, type = "application/json") |> httr2::req_error(is_error = function(resp) FALSE)
  resp <- httr2::req_perform_connection(req, blocking = TRUE)
  on.exit(close(resp), add = TRUE)
  stamps <- numeric(0)
  repeat {
    ev <- httr2::resp_stream_sse(resp)
    if (is.null(ev)) { if (httr2::resp_stream_is_complete(resp)) break else next }
    stamps <- c(stamps, now())
    if (isTRUE(on_sse(list(event = ev$type, data = ev$data)))) break
  }
  list(status = httr2::resp_status(resp), headers = as.list(httr2::resp_headers(resp)), stamps = stamps)
}

# ---------------------------------------------------------------------------
# 4. Provider front-ends
# ---------------------------------------------------------------------------
oai_chat_stream <- function(base_url, api_key, body, transport = transport_curl, on_event = NULL,
                            extra_headers = list(), supports_finish_reason = TRUE) {
  body$stream <- TRUE
  body$stream_options <- body$stream_options %||% list(include_usage = TRUE)
  acc <- oai_accumulator_new(on_event, supports_finish_reason)
  url <- paste0(sub("/+$", "", base_url), "/chat/completions")
  hdr <- c(list(Authorization = paste("Bearer", api_key), Accept = "text/event-stream",
                `Content-Type` = "application/json"), extra_headers)
  tr <- transport(url, hdr, jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA), acc$push_sse)
  c(acc$result(), list(http_status = tr$status, request_id = tr$headers[["x-request-id"]], stamps = tr$stamps))
}

gemini_stream <- function(base_url, api_key, model, body, transport = transport_curl, on_event = NULL) {
  acc <- gemini_accumulator_new(on_event)
  url <- sprintf("%s/models/%s:streamGenerateContent?alt=sse", sub("/+$", "", base_url), model)
  hdr <- list(`x-goog-api-key` = api_key, Accept = "text/event-stream", `Content-Type` = "application/json")
  tr <- transport(url, hdr, jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA), acc$push_sse)
  c(acc$result(), list(http_status = tr$status, stamps = tr$stamps))
}
```

`SCR/v2/mock_server.R` (complete; pure ASCII, base R sockets, chunked transfer encoding, every event split mid-bytes):
```r
# Mock LLM server in base R (serverSocket), used to test gptr-style streaming clients.
# Source is pure ASCII: every non-ASCII character is written as a \u escape so the
# file behaves identically in a C / non-UTF-8 locale (as on some Windows setups).
#
# Usage: Rscript --vanilla mock_server.R <port> <n_connections>
# Routes
#   POST /v1/chat/completions                      OpenAI-compatible, Authorization: Bearer test-key
#        model "mock-text" | "mock-tools" | "mock-error" | "mock-slow"
#   POST /v1beta/models/<model>:streamGenerateContent?alt=sse   Gemini, x-goog-api-key: test-key
#        model "gemini-mock" (thought + text + functionCall) | "gemini-slow"
# Every SSE event is written in two TCP writes split at an arbitrary byte offset
# (so multi-byte UTF-8 characters and JSON tokens are cut), CRLF and LF event
# terminators alternate, and SSE comment lines are injected.
suppressPackageStartupMessages(library(jsonlite))
args <- commandArgs(trailingOnly = TRUE)
port <- as.integer(args[[1]]); n_conn <- as.integer(args[[2]])
j <- function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
EMPTY <- structure(list(), names = character(0))
U <- function(...) intToUtf8(c(...))  # ASCII-safe construction of non-ASCII text
O_UML <- U(0xF6); NIHAO <- U(0x4F60, 0x597D); EMOJI <- U(0x1F600); EMDASH <- U(0x2014); E_ACUTE <- U(0xE9)

oa_chunk <- function(delta, finish = NULL, usage = NULL, choices = TRUE, extra = list()) {
  o <- list(id = "chatcmpl-mock-1", object = "chat.completion.chunk", created = 1790000000L, model = "mock-model-2026")
  o$choices <- if (choices) list(list(index = 0L, delta = delta, finish_reason = finish)) else list()
  if (!is.null(usage)) o$usage <- usage
  c(o, extra)
}
oa_usage <- list(prompt_tokens = 42L, completion_tokens = 17L, total_tokens = 59L,
                 prompt_tokens_details = list(cached_tokens = 30L),
                 completion_tokens_details = list(reasoning_tokens = 6L))
d <- function(x) paste0("data: ", j(x))
tc <- function(index, id = NULL, name = NULL, arguments = NULL) {
  f <- list(); if (!is.null(name)) f$name <- name; if (!is.null(arguments)) f$arguments <- arguments
  o <- list(index = index); if (!is.null(id)) { o$id <- id; o$type <- "function" }
  o[["function"]] <- f
  list(tool_calls = list(o))
}
sc_text <- function() list(
  ": OPENROUTER PROCESSING",
  d(oa_chunk(list(role = "assistant", content = ""))),
  d(oa_chunk(list(reasoning_content = "Let me think"))),
  d(oa_chunk(list(reasoning_content = " about it."))),
  d(oa_chunk(list(content = paste0("Hello, w", O_UML, "rld")))),
  d(oa_chunk(list(content = paste0(" ", NIHAO, " ", EMOJI)))),
  d(oa_chunk(list(content = "!"))),
  d(oa_chunk(EMPTY, finish = "stop")),
  d(oa_chunk(NULL, usage = oa_usage, choices = FALSE)),
  "data: [DONE]")
sc_tools <- function() list(
  d(oa_chunk(list(role = "assistant", content = NULL))),
  d(oa_chunk(tc(0L, "call_abc123", "r_eval", ""))),
  d(oa_chunk(tc(0L, arguments = "{\"co"))),
  d(oa_chunk(tc(0L, arguments = "de\":\"summary("))),
  d(oa_chunk(tc(0L, arguments = "mtcars$mpg)\"}"))),
  d(oa_chunk(tc(1L, "call_def456", "read_file", "{\"path\":"))),
  d(oa_chunk(tc(1L, arguments = "\"R/a.R\"}"))),
  d(oa_chunk(EMPTY, finish = "tool_calls"))
  # no usage chunk and no [DONE]: some servers close the stream right after finish_reason
)
sc_error <- function() list(
  d(oa_chunk(list(role = "assistant", content = ""))),
  d(oa_chunk(list(content = "partial "))),
  d(oa_chunk(list(content = ""), finish = "error",
             extra = list(error = list(code = 502L, message = "Provider disconnected unexpectedly")))))
sc_slow <- function() c(list(d(oa_chunk(list(role = "assistant", content = "")))),
  lapply(sprintf("tok%02d ", 1:8), function(t) d(oa_chunk(list(content = t)))),
  list(d(oa_chunk(EMPTY, finish = "stop")), "data: [DONE]"))

gm_chunk <- function(parts = NULL, finish = NULL, usage = NULL) {
  o <- list()
  if (!is.null(parts) || !is.null(finish)) {
    cand <- list(content = list(parts = parts %||% list(), role = "model"), index = 0L)
    if (!is.null(finish)) cand$finishReason <- finish
    o$candidates <- list(cand)
  }
  if (!is.null(usage)) o$usageMetadata <- usage
  o$modelVersion <- "gemini-mock-001"; o$responseId <- "resp-gm-1"
  o
}
`%||%` <- function(x, y) if (is.null(x)) y else x
gm_usage <- list(promptTokenCount = 120L, cachedContentTokenCount = 100L, candidatesTokenCount = 25L,
                 thoughtsTokenCount = 40L, totalTokenCount = 185L)
sc_gemini <- function() list(
  d(gm_chunk(list(list(text = "**Planning** I should inspect the data.", thought = TRUE)))),
  d(gm_chunk(list(list(text = " Then summarise it.", thought = TRUE)))),
  d(gm_chunk(list(list(text = "I will look at "))))
  , d(gm_chunk(list(list(text = paste0("mtcars ", EMDASH, " caf", E_ACUTE, " ", EMOJI, "."), thoughtSignature = "c2lnLXRleHQ=")))),
  d(gm_chunk(list(
    list(functionCall = list(id = "fc_1", name = "r_eval", args = list(code = "summary(mtcars$mpg)")),
         thoughtSignature = "c2lnLWZjMQ=="),
    list(functionCall = list(id = "fc_2", name = "read_file", args = list(path = "R/a.R")))),
    finish = "STOP", usage = gm_usage)))
sc_gemini_slow <- function() c(
  lapply(sprintf("tok%02d ", 1:8), function(t) d(gm_chunk(list(list(text = t)))) ),
  list(d(gm_chunk(list(list(text = ".")), finish = "STOP",
       usage = list(promptTokenCount = 5L, candidatesTokenCount = 9L, totalTokenCount = 14L)))))

read_request <- function(con) {
  buf <- raw(0); term <- charToRaw("\r\n\r\n")
  repeat {
    b <- readBin(con, "raw", 1L)
    if (length(b) == 0L) { Sys.sleep(0.005); next }
    buf <- c(buf, b); n <- length(buf)
    if (n >= 4L && identical(buf[(n - 3L):n], term)) break
  }
  head <- strsplit(rawToChar(buf), "\r\n", fixed = TRUE)[[1]]
  rl <- strsplit(head[[1]], " ", fixed = TRUE)[[1]]
  hl <- head[-1]; hl <- hl[nzchar(hl)]
  headers <- as.list(setNames(trimws(sub("^[^:]*:", "", hl)), tolower(sub(":.*$", "", hl))))
  len <- as.integer(headers[["content-length"]] %||% "0"); body <- raw(0)
  while (length(body) < len) { b <- readBin(con, "raw", len - length(body)); if (length(b)) body <- c(body, b) else Sys.sleep(0.005) }
  list(method = rl[[1]], path = rl[[2]], headers = headers, body = rawToChar(body))
}
send_raw <- function(con, x) { writeBin(x, con); flush(con) }
send_chunk <- function(con, data) send_raw(con, c(charToRaw(sprintf("%x\r\n", length(data))), data, charToRaw("\r\n")))
respond_json <- function(con, status, reason, obj) {
  body <- charToRaw(enc2utf8(j(obj)))
  send_raw(con, c(charToRaw(sprintf("HTTP/1.1 %d %s\r\nContent-Type: application/json; charset=UTF-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n", status, reason, length(body))), body))
}
respond_stream <- function(con, events, gap = 0.05, split = TRUE) {
  send_raw(con, charToRaw(paste0("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n",
                                 "x-request-id: mock-req-1\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")))
  i <- 0L
  for (ev in events) {
    i <- i + 1L
    eol <- if (i %% 2L == 0L) "\r\n\r\n" else "\n\n"
    bytes <- charToRaw(enc2utf8(paste0(ev, eol)))
    if (split && length(bytes) > 14L) {
      cut <- length(bytes) - 12L          # lands inside the multi-byte tail / JSON
      send_chunk(con, bytes[seq_len(cut)]); Sys.sleep(0.01)
      send_chunk(con, bytes[(cut + 1L):length(bytes)])
    } else send_chunk(con, bytes)
    Sys.sleep(gap)
  }
  send_raw(con, charToRaw("0\r\n\r\n"))
}

srv <- serverSocket(port)
cat("READY\n"); flush(stdout())
for (k in seq_len(n_conn)) {
  con <- socketAccept(srv, blocking = TRUE, open = "r+b", timeout = 120)
  res <- tryCatch({
    rq <- read_request(con)
    body <- if (nzchar(rq$body)) fromJSON(rq$body, simplifyVector = FALSE) else list()
    if (grepl("/chat/completions$", rq$path)) {
      if (!identical(rq$headers[["authorization"]], "Bearer test-key")) {
        respond_json(con, 401L, "Unauthorized", list(error = list(message = "Incorrect API key provided.",
          type = "invalid_request_error", param = NULL, code = "invalid_api_key")))
      } else switch(body$model,
        "mock-text" = respond_stream(con, sc_text()),
        "mock-tools" = respond_stream(con, sc_tools()),
        "mock-error" = respond_stream(con, sc_error()),
        "mock-slow" = respond_stream(con, sc_slow(), gap = 0.25, split = FALSE),
        respond_json(con, 404L, "Not Found", list(error = list(message = "model not found"))))
    } else if (grepl(":streamGenerateContent\\?alt=sse$", rq$path)) {
      if (!identical(rq$headers[["x-goog-api-key"]], "test-key")) {
        respond_json(con, 400L, "Bad Request", list(error = list(code = 400L,
          message = "API key not valid. Please pass a valid API key.", status = "INVALID_ARGUMENT")))
      } else if (grepl("gemini-slow", rq$path)) respond_stream(con, sc_gemini_slow(), gap = 0.25, split = FALSE)
      else respond_stream(con, sc_gemini())
    } else respond_json(con, 404L, "Not Found", list(error = list(message = "unknown route")))
    sprintf("%s %s ok", rq$method, rq$path)
  }, error = function(e) paste("server error:", conditionMessage(e)))
  cat(sprintf("conn %d: %s\n", k, res)); flush(stdout())
  try(close(con), silent = TRUE)
}
close(srv)
```
(The header comment's "\u escape" wording predates the switch to `intToUtf8()`; `LC_ALL=C grep -P '[^\x00-\x7F]'` on the file returns 0 lines.)

`SCR/v2/run_stream_tests.R` (driver; starts the mock in a background `Rscript` via processx, runs every scenario on two
transports, then a latency test on three):
```r
suppressPackageStartupMessages({ library(jsonlite) })
wd <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-09/v2"
source(file.path(wd, "stream_client.R"))
cat("R", as.character(getRversion()), "| locale:", Sys.getlocale("LC_CTYPE"), "| httr2", as.character(packageVersion("httr2")),
    "| curl", as.character(packageVersion("curl")), "(libcurl", curl::curl_version()$version, ")\n")

port <- httpuv::randomPort()
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
srv <- processx::process$new(rscript, c("--vanilla", file.path(wd, "mock_server.R"), port, 40), stdout = "|", stderr = "|")
t0 <- now()
repeat { srv$poll_io(200); if (any(grepl("READY", srv$read_output_lines()))) break
         if (!srv$is_alive() || now() - t0 > 15) stop("server failed: ", srv$read_all_error()) }
oa_base <- sprintf("http://127.0.0.1:%d/v1", port)
gm_base <- sprintf("http://127.0.0.1:%d/v1beta", port)

msgs <- list(list(role = "system", content = "You are terse."), list(role = "user", content = "Say hello"))
tool_def <- list(type = "function", `function` = list(name = "r_eval", description = "Evaluate R code in the live session",
  parameters = list(type = "object", properties = list(code = list(type = "string")), required = list("code"))))
oa_body <- function(model, tools = FALSE) { b <- list(model = model, messages = msgs, max_completion_tokens = 64L)
                                            if (tools) b$tools <- list(tool_def); b }
gm_body <- list(
  systemInstruction = list(parts = list(list(text = "You are terse."))),
  contents = list(list(role = "user", parts = list(list(text = "Summarise mtcars$mpg")))),
  tools = list(list(functionDeclarations = list(list(name = "r_eval", description = "Evaluate R code",
    parametersJsonSchema = list(type = "object", properties = list(code = list(type = "string")), required = list("code")))))),
  toolConfig = list(functionCallingConfig = list(mode = "AUTO")),
  generationConfig = list(maxOutputTokens = 1024L, thinkingConfig = list(includeThoughts = TRUE, thinkingLevel = "low")))
cat("\nGemini request body sent:\n", toJSON(gm_body, auto_unbox = TRUE, pretty = FALSE), "\n")

show_oa <- function(label, r) {
  cat(sprintf("\n== %s ==\n", label))
  cat("status", r$http_status, "| request_id", r$request_id %||% "-", "| [DONE] seen", r$got_done_sentinel, "\n")
  cat("text    :", encodeString(r$text, quote = '"'), "| valid UTF-8", validUTF8(r$text), "| nchar", nchar(r$text), "\n")
  cat("thinking:", encodeString(r$thinking, quote = '"'), "(field", r$thinking_field %||% "-", ")\n")
  for (t in r$tool_calls) cat("tool    :", t$id, t$name, as.character(toJSON(t$arguments, auto_unbox = TRUE)), "\n")
  cat("stop    :", r$stop_reason, "(raw", r$raw_finish %||% "NULL", ") error:", r$error %||% "-", "\n")
  cat("usage   :", as.character(toJSON(r$usage, auto_unbox = TRUE)), "\n")
}
timing <- function(label, st) {
  g <- diff(st)
  cat(sprintf("  %-34s events=%2d  spread=%.2fs  max_gap=%.2fs  median_gap=%.2fs  batched=%s\n", label, length(st),
              max(st) - min(st), max(g), stats::median(g), stats::median(g) < 0.05))
}
expected_text <- paste0("Hello, w", intToUtf8(0xF6), "rld ", intToUtf8(c(0x4F60, 0x597D)), " ", intToUtf8(0x1F600), "!")

res <- list()
for (tn in c("curl", "httr2_poll")) {
  tr <- get(paste0("transport_", tn))
  deltas <- character(0)
  r1 <- oai_chat_stream(oa_base, "test-key", oa_body("mock-text"), transport = tr,
                        on_event = function(e) if (e$type == "text_delta") deltas <<- c(deltas, e$delta))
  show_oa(paste(tn, "/ openai text + reasoning_content"), r1)
  cat("deltas  :", length(deltas), "text deltas; equals expected:", identical(r1$text, expected_text), "\n")
  r2 <- oai_chat_stream(oa_base, "test-key", oa_body("mock-tools", TRUE), transport = tr)
  show_oa(paste(tn, "/ openai parallel tool calls, no [DONE]"), r2)
  r3 <- oai_chat_stream(oa_base, "test-key", oa_body("mock-error"), transport = tr)
  show_oa(paste(tn, "/ openai mid-stream error chunk"), r3)
  e <- tryCatch(oai_chat_stream(oa_base, "wrong-key", oa_body("mock-text"), transport = tr), error = function(e) e)
  cat(sprintf("\n== %s / openai 401 ==\n%s | %s | status %s\n", tn, class(e)[1], conditionMessage(e), e$status))
  g <- gemini_stream(gm_base, "test-key", "gemini-mock", gm_body, transport = tr)
  cat(sprintf("\n== %s / gemini thought + text + parallel functionCall ==\n", tn))
  cat("status", g$http_status, "| responseId", g$response_id, "| modelVersion", g$model_version, "\n")
  for (b in g$blocks) {
    if (b$type == "tool_call") cat(sprintf("  [tool_call] id=%s name=%s args=%s signature=%s\n", b$id, b$name,
                                         as.character(toJSON(b$arguments, auto_unbox = TRUE)), b$signature %||% "<none>"))
    else cat(sprintf("  [%s] %s | signature=%s\n", b$type, encodeString(b$text, quote = '"'), b$signature %||% "<none>"))
  }
  cat("stop:", g$stop_reason, "(raw", g$raw_finish, ") usage:", as.character(toJSON(g$usage, auto_unbox = TRUE)), "\n")
  e2 <- tryCatch(gemini_stream(gm_base, "wrong", "gemini-mock", gm_body, transport = tr), error = function(e) e)
  cat(sprintf("gemini bad key -> %s | %s\n", class(e2)[1], conditionMessage(e2)))
  res[[tn]] <- list(r1 = r1, r2 = r2, g = g)
}

cat("\n== equivalence curl vs httr2_poll ==\n")
strip <- function(r) r[c("text", "thinking", "tool_calls", "stop_reason", "usage")]
cat("openai text :", identical(strip(res$curl$r1), strip(res$httr2_poll$r1)), "\n")
cat("openai tools:", identical(strip(res$curl$r2), strip(res$httr2_poll$r2)), "\n")
cat("gemini      :", identical(res$curl$g[c("blocks", "usage", "stop_reason")], res$httr2_poll$g[c("blocks", "usage", "stop_reason")]), "\n")

cat("\n== streaming latency: server emits one small event every 250 ms ==\n")
for (tn in c("curl", "httr2_poll", "httr2_sse_blocking")) {
  tr <- get(paste0("transport_", tn))
  r <- oai_chat_stream(oa_base, "test-key", oa_body("mock-slow"), transport = tr)
  timing(paste(tn, "/ openai"), r$stamps)
  g <- gemini_stream(gm_base, "test-key", "gemini-slow", gm_body, transport = tr)
  timing(paste(tn, "/ gemini"), g$stamps)
  if (tn == "httr2_sse_blocking") cat("  (text check:", encodeString(r$text), ")\n")
}
srv$kill()
```

Observed output (executed `Rscript --vanilla run_stream_tests.R`, 20 s wall clock; the second transport's block is identical
and abbreviated):
```
R 4.4.3 | locale: C | httr2 1.2.2 | curl 7.0.0 (libcurl 8.14.1 )

Gemini request body sent:
 {"systemInstruction":{"parts":[{"text":"You are terse."}]},"contents":[{"role":"user","parts":[{"text":"Summarise mtcars$mpg"}]}],"tools":[{"functionDeclarations":[{"name":"r_eval","description":"Evaluate R code","parametersJsonSchema":{"type":"object","properties":{"code":{"type":"string"}},"required":["code"]}}]}],"toolConfig":{"functionCallingConfig":{"mode":"AUTO"}},"generationConfig":{"maxOutputTokens":1024,"thinkingConfig":{"includeThoughts":true,"thinkingLevel":"low"}}}

== curl / openai text + reasoning_content ==
status 200 | request_id mock-req-1 | [DONE] seen TRUE
text    : "Hello, w<U+00F6>rld <U+4F60><U+597D> <U+0001F600>!" | valid UTF-8 TRUE | nchar 18
thinking: "Let me think about it." (field reasoning_content )
stop    : stop (raw stop ) error: -
usage   : {"input":12,"output":17,"cache_read":30,"cache_write":0,"reasoning":6}
deltas  : 3 text deltas; equals expected: TRUE

== curl / openai parallel tool calls, no [DONE] ==
status 200 | request_id mock-req-1 | [DONE] seen FALSE
text    : "" | valid UTF-8 TRUE | nchar 0
thinking: "" (field - )
tool    : call_abc123 r_eval {"code":"summary(mtcars$mpg)"}
tool    : call_def456 read_file {"path":"R/a.R"}
stop    : tool_use (raw tool_calls ) error: -
usage   : {"input":0,"output":0,"cache_read":0,"cache_write":0,"reasoning":0}

== curl / openai mid-stream error chunk ==
status 200 | request_id mock-req-1 | [DONE] seen FALSE
text    : "partial " | valid UTF-8 TRUE | nchar 8
thinking: "" (field - )
stop    : error (raw error ) error: Provider disconnected unexpectedly
usage   : {"input":0,"output":0,"cache_read":0,"cache_write":0,"reasoning":0}

== curl / openai 401 ==
gptr_http_error | HTTP 401: Incorrect API key provided. | status 401

== curl / gemini thought + text + parallel functionCall ==
status 200 | responseId resp-gm-1 | modelVersion gemini-mock-001
  [thinking] "**Planning** I should inspect the data. Then summarise it." | signature=<none>
  [text] "I will look at mtcars <U+2014> caf<U+00E9> <U+0001F600>." | signature=c2lnLXRleHQ=
  [tool_call] id=fc_1 name=r_eval args={"code":"summary(mtcars$mpg)"} signature=c2lnLWZjMQ==
  [tool_call] id=fc_2 name=read_file args={"path":"R/a.R"} signature=<none>
stop: tool_use (raw STOP ) usage: {"input":20,"output":65,"cache_read":100,"cache_write":0,"reasoning":40,"total":185}
gemini bad key -> gptr_http_error | HTTP 400: API key not valid. Please pass a valid API key.

== httr2_poll / ... (identical to the curl blocks above) ...

== equivalence curl vs httr2_poll ==
openai text : TRUE
openai tools: TRUE
gemini      : TRUE

== streaming latency: server emits one small event every 250 ms ==
  curl / openai                      events=11  spread=2.55s  max_gap=0.26s  median_gap=0.25s  batched=FALSE
  curl / gemini                      events= 9  spread=2.03s  max_gap=0.26s  median_gap=0.25s  batched=FALSE
  httr2_poll / openai                events=11  spread=2.57s  max_gap=0.27s  median_gap=0.26s  batched=FALSE
  httr2_poll / gemini                events= 9  spread=2.04s  max_gap=0.27s  median_gap=0.25s  batched=FALSE
  httr2_sse_blocking / openai        events=11  spread=1.53s  max_gap=1.53s  median_gap=0.00s  batched=TRUE
  httr2_sse_blocking / gemini        events= 9  spread=0.77s  max_gap=0.76s  median_gap=0.00s  batched=TRUE
  (text check: tok01 tok02 tok03 tok04 tok05 tok06 tok07 tok08  )
```
What this proves: SSE streaming works in R on this machine, parsing is byte-exact across splits in a C locale, the curl-multi
and httr2-non-blocking transports agree, a missing `[DONE]` and mid-stream error chunks are handled, and HTTP errors map to a
classed condition. Printing shows `<U+...>` escapes only because the C locale cannot display them; `validUTF8()` and
`identical(expected)` are TRUE.

### 5.2 Blocking-read mechanism behind httr2's SSE batching

`SCR/v2/test_blocking_mechanism.R` (sources `stream_client.R` for `now()`; same mock, `mock-slow`):
```r
wd <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-09/v2"
source(file.path(wd, "stream_client.R"))
port <- httpuv::randomPort()
srv <- processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", file.path(wd, "mock_server.R"), port, 3), stdout = "|", stderr = "|")
repeat { srv$poll_io(200); if (any(grepl("READY", srv$read_output_lines()))) break }
body <- '{"model":"mock-slow","messages":[{"role":"user","content":"x"}],"stream":true}'
for (kb in c(1, 0.25, 1/16)) {
  req <- httr2::request(sprintf("http://127.0.0.1:%d/v1/chat/completions", port)) |>
    httr2::req_headers(Authorization = "Bearer test-key") |> httr2::req_body_raw(body, type = "application/json")
  resp <- httr2::req_perform_connection(req, blocking = TRUE)
  t0 <- now(); reads <- c(); sizes <- c()
  while (!httr2::resp_stream_is_complete(resp)) {
    x <- httr2::resp_stream_raw(resp, kb = kb)
    if (length(x)) { reads <- c(reads, now() - t0); sizes <- c(sizes, length(x)) }
  }
  close(resp)
  cat(sprintf("blocking read of %4d bytes: %2d reads; first data after %.2fs; sizes %s\n  read times: %s\n", as.integer(kb * 1024),
      length(reads), reads[1], paste(head(sizes, 8), collapse = ","), paste(sprintf("%.2f", reads), collapse = " ")))
}
srv$kill()
```
Output:
```
blocking read of 1024 bytes:  2 reads; first data after 1.30s; sizes 1024,857
  read times: 1.30 2.80
blocking read of  256 bytes:  8 reads; first data after 0.26s; sizes 256,256,256,256,256,256,256,89
  read times: 0.26 0.51 1.02 1.27 1.54 2.05 2.30 2.80
blocking read of   64 bytes: 30 reads; first data after 0.00s; sizes 64,64,64,64,64,64,64,64
  read times: 0.00 0.00 0.00 0.25 0.25 0.25 0.51 0.51 0.76 0.76 0.76 1.02 1.02 1.02 1.28 1.28 1.28 1.53 1.53 1.53 1.78 1.79 1.79 2.04 2.04 2.04 2.29 2.29 2.29 2.80
```
Combined with httr2's source (`resp_boundary_pushback`: `chunk_size <- min(max_size + 1, 1024)`), this explains the bursts.

### 5.3 Pure-R SigV4, verified against AWS vectors and libcurl

`SCR/v2/sigv4.R` (complete):
```r
# Pure-R AWS Signature Version 4 (header signing), openssl only.
# Spec: https://docs.aws.amazon.com/IAM/latest/UserGuide/create-signed-request.html
# Test vectors: awslabs/aws-c-auth tests/aws-signing-test-suite/v4/{get-vanilla,post-x-www-form-urlencoded}

`%||%` <- function(x, y) if (is.null(x)) y else x

hex <- function(x) paste(as.character(unclass(x)), collapse = "")
sha256_hex <- function(x) {
  if (is.character(x)) x <- charToRaw(enc2utf8(x))
  hex(openssl::sha256(x))
}
hmac_raw <- function(key, msg) {
  if (is.character(key)) key <- charToRaw(enc2utf8(key))
  as.raw(unclass(openssl::sha256(charToRaw(enc2utf8(msg)), key = key)))
}

# RFC 3986 unreserved set; AWS "UriEncode" (encode_slash = FALSE for paths)
aws_uri_encode <- function(x, encode_slash = TRUE) {
  vapply(x, function(s) {
    bytes <- charToRaw(enc2utf8(s))
    out <- character(length(bytes))
    for (i in seq_along(bytes)) {
      ch <- rawToChar(bytes[i])
      if (grepl("^[A-Za-z0-9_.~-]$", ch) || (!encode_slash && ch == "/")) out[i] <- ch
      else out[i] <- sprintf("%%%02X", as.integer(bytes[i]))
    }
    paste(out, collapse = "")
  }, "", USE.NAMES = FALSE)
}

#' Sign a request. Returns the headers to add (authorization, x-amz-date, and
#' optionally x-amz-content-sha256 / x-amz-security-token) plus debug fields.
aws_sigv4_sign <- function(method, url, headers = list(), body = raw(0),
                           access_key, secret_key, session_token = NULL,
                           region, service, time = Sys.time(),
                           sign_body = TRUE) {
  if (is.character(body)) body <- charToRaw(enc2utf8(body))
  u <- regmatches(url, regexec("^(https?)://([^/?#]+)([^?#]*)(\\?[^#]*)?", url))[[1]]
  host <- u[3]; path <- if (nzchar(u[4])) u[4] else "/"
  query <- sub("^\\?", "", u[5])
  amz_date <- format(as.POSIXct(time, tz = "UTC"), "%Y%m%dT%H%M%SZ", tz = "UTC")
  date <- substr(amz_date, 1, 8)
  payload_hash <- sha256_hex(body)

  h <- headers
  names(h) <- tolower(names(h))
  h[["host"]] <- h[["host"]] %||% host
  h[["x-amz-date"]] <- amz_date
  if (sign_body) h[["x-amz-content-sha256"]] <- payload_hash
  if (!is.null(session_token)) h[["x-amz-security-token"]] <- session_token
  h <- h[order(names(h))]
  canon_headers <- paste0(names(h), ":", vapply(h, function(v) gsub("\\s+", " ", trimws(v)), ""), "\n",
                          collapse = "")
  signed_headers <- paste(names(h), collapse = ";")

  # canonical path: each segment URI-encoded once (services other than S3 double
  # encode; Bedrock model ids containing ':' must be encoded as %3A)
  segs <- strsplit(path, "/", fixed = TRUE)[[1]]
  canon_path <- paste(aws_uri_encode(segs), collapse = "/")  # encode the path AS SENT (double-encodes %XX)
  if (endsWith(path, "/") && !endsWith(canon_path, "/")) canon_path <- paste0(canon_path, "/")
  if (!nzchar(canon_path)) canon_path <- "/"
  canon_query <- ""
  if (!is.na(query) && nzchar(query)) {
    kv <- strsplit(strsplit(query, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
    k <- aws_uri_encode(vapply(kv, `[`, "", 1)); v <- aws_uri_encode(vapply(kv, function(p) if (length(p) > 1) p[2] else "", ""))
    o <- order(k, v); canon_query <- paste0(k[o], "=", v[o], collapse = "&")
  }
  canonical_request <- paste(method, canon_path, canon_query, canon_headers, signed_headers,
                             payload_hash, sep = "\n")
  scope <- paste(date, region, service, "aws4_request", sep = "/")
  string_to_sign <- paste("AWS4-HMAC-SHA256", amz_date, scope, sha256_hex(canonical_request), sep = "\n")
  k_date <- hmac_raw(paste0("AWS4", secret_key), date)
  k_region <- hmac_raw(k_date, region)
  k_service <- hmac_raw(k_region, service)
  k_signing <- hmac_raw(k_service, "aws4_request")
  signature <- hex(openssl::sha256(charToRaw(string_to_sign), key = k_signing))
  auth <- sprintf("AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s",
                  access_key, scope, signed_headers, signature)
  out <- list(authorization = auth, `x-amz-date` = amz_date)
  if (sign_body) out[["x-amz-content-sha256"]] <- payload_hash
  if (!is.null(session_token)) out[["x-amz-security-token"]] <- session_token
  structure(out, canonical_request = canonical_request, string_to_sign = string_to_sign,
            signature = signature)
}
```
(The comment above `segs` is stale; the code encodes the path exactly as sent, which the libcurl comparison below confirms.)

Test `SCR/v2/test_sigv4.R` (the AWS vectors, then a libcurl cross-check through a one-shot capture server in a `callr::r_bg()`
process; full file in scratch). Output:
```
== AWS test vector get-vanilla (sign_body = false)
GET
/

host:example.amazonaws.com
x-amz-date:20150830T123600Z

host;x-amz-date
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
---
signature: 5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31
matches expected 5fa00fa3...: TRUE

== AWS test vector post-x-www-form-urlencoded (sign_body = true)
POST
/

content-length:13
content-type:application/x-www-form-urlencoded
host:example.amazonaws.com
x-amz-content-sha256:9095672bbd1f56dfc5b65f3e153adc8731a4a654192329106275f4c7b24d0b6e
x-amz-date:20150830T123600Z

content-length;content-type;host;x-amz-content-sha256;x-amz-date
9095672bbd1f56dfc5b65f3e153adc8731a4a654192329106275f4c7b24d0b6e
---
signature: d3875051da38690788ef43de4db0d8f280229d82040bfac253562e56c3f20e0b
matches expected d3875051...: TRUE

== cross-check with libcurl aws_sigv4 (curl 8.14.1 )
request line: POST /model/us.anthropic.claude-sonnet-4-6/converse HTTP/1.1
curl Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260930/us-east-1/bedrock/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=2d5b5bcc176e1c5c850c23578a739ccf00e3cb74750307b9dc368855d56cdaa6
curl signed headers: content-type;host;x-amz-date
R  Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260930/us-east-1/bedrock/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=2d5b5bcc176e1c5c850c23578a739ccf00e3cb74750307b9dc368855d56cdaa6
identical to libcurl: TRUE
```
The canonical requests match the published `header-canonical-request.txt` files (fetched from `awslabs/aws-c-auth`).
`SCR/v2/test_sigv4_colon.R` output (colon model IDs):
```
path given to curl: /model/anthropic.claude-3-5-sonnet-20240620-v1:0/converse-stream wire: /model/anthropic.claude-3-5-sonnet-20240620-v1:0/converse-stream
  R canonical path: /model/anthropic.claude-3-5-sonnet-20240620-v1%3A0/converse-stream
  identical to libcurl: TRUE
path given to curl: /model/anthropic.claude-3-5-sonnet-20240620-v1%3A0/converse-stream wire: /model/anthropic.claude-3-5-sonnet-20240620-v1%3A0/converse-stream
  R canonical path: /model/anthropic.claude-3-5-sonnet-20240620-v1%253A0/converse-stream
  identical to libcurl: TRUE
```
Not verified: acceptance by real AWS (no credentials used). Matching libcurl and the AWS vectors makes it LIKELY.
**Verifier finding (limitation, fix before using query strings):** the canonical-query code splits each pair on every `=` and
keeps only the second piece, so `x=a=b` canonicalises to `x=a`; it also re-encodes values that are already percent-encoded
(`a%20b` becomes `a%2520b`), whereas SigV4 wants each decoded name/value encoded exactly once. Converse/ConverseStream and the
`/openai/v1/chat/completions` path send no query string, so the Bedrock paths above are unaffected; `ListFoundationModels`
(`?byProvider=...`) with simple values also works. Split on the first `=` only and URL-decode before encoding when porting.

### 5.4 AWS event-stream codec in pure R

`SCR/v2/eventstream.R` (complete):
```r
# AWS binary event stream (application/vnd.amazon.eventstream) in pure R.
# Spec: https://smithy.io/2.0/aws/amazon-eventstream.html
# Message: uint32 total_len | uint32 headers_len | uint32 prelude_crc | headers | payload | uint32 message_crc
# CRC32 = IEEE 802.3 / gzip CRC32; all integers big-endian.

# bitwXor works on 32-bit signed ints; keep values as doubles in [0, 2^32) and
# XOR via the two 16-bit halves to avoid overflow.
xor32 <- function(a, b) {
  ah <- a %/% 65536; al <- a %% 65536; bh <- b %/% 65536; bl <- b %% 65536
  bitwXor(ah, bh) * 65536 + bitwXor(al, bl)
}
crc32_raw <- function(bytes) {
  crc <- 0xFFFFFFFF
  for (b in as.integer(bytes)) {
    idx <- bitwXor(as.integer(crc %% 256), b) + 1
    crc <- xor32(crc %/% 256, crc32_table_ok[idx])
  }
  xor32(crc, 0xFFFFFFFF)
}
# (re)build the table with the safe xor
crc32_table_ok <- local({
  tab <- numeric(256)
  for (n in 0:255) {
    c <- n
    for (k in 1:8) c <- if (c %% 2 == 1) xor32(0xEDB88320, c %/% 2) else c %/% 2
    tab[n + 1] <- c
  }
  tab
})

u32_be <- function(x) as.raw(c(x %/% 2^24, (x %/% 2^16) %% 256, (x %/% 2^8) %% 256, x %% 256))
read_u32_be <- function(b, i) sum(as.numeric(as.integer(b[i:(i + 3)])) * c(2^24, 2^16, 2^8, 1))
read_u16_be <- function(b, i) as.integer(b[i]) * 256L + as.integer(b[i + 1])

es_encode <- function(headers, payload) {
  if (is.character(payload)) payload <- charToRaw(enc2utf8(payload))
  hb <- raw(0)
  for (nm in names(headers)) {
    v <- charToRaw(enc2utf8(headers[[nm]])); n <- charToRaw(nm)
    hb <- c(hb, as.raw(length(n)), n, as.raw(7L), as.raw(c(length(v) %/% 256, length(v) %% 256)), v)
  }
  total <- 12 + length(hb) + length(payload) + 4
  prelude <- c(u32_be(total), u32_be(length(hb)))
  msg <- c(prelude, u32_be(crc32_raw(prelude)), hb, payload)
  c(msg, u32_be(crc32_raw(msg)))
}

es_parse_headers <- function(hb) {
  out <- list(); i <- 1L
  while (i <= length(hb)) {
    nlen <- as.integer(hb[i]); name <- rawToChar(hb[(i + 1):(i + nlen)]); i <- i + 1L + nlen
    type <- as.integer(hb[i]); i <- i + 1L
    val <- switch(as.character(type),
      "0" = TRUE, "1" = FALSE,
      "2" = { v <- as.integer(hb[i]); i <- i + 1L; v },
      "3" = { v <- read_u16_be(hb, i); i <- i + 2L; v },
      "4" = { v <- read_u32_be(hb, i); i <- i + 4L; v },
      "5" = { v <- sum(as.numeric(as.integer(hb[i:(i + 7)])) * 256^(7:0)); i <- i + 8L; v },
      "6" = , "7" = { l <- read_u16_be(hb, i); v <- hb[(i + 2):(i + 1 + l)]; i <- i + 2L + l
                      if (type == 7L) { s <- rawToChar(v); Encoding(s) <- "UTF-8"; s } else v },
      "8" = { v <- sum(as.numeric(as.integer(hb[i:(i + 7)])) * 256^(7:0)); i <- i + 8L
              as.POSIXct(v / 1000, origin = "1970-01-01", tz = "UTC") },
      "9" = { v <- hb[i:(i + 15)]; i <- i + 16L; paste(as.character(v), collapse = "") },
      stop("unknown eventstream header type ", type))
    out[[name]] <- val
  }
  out
}

#' Incremental decoder: $feed(raw) returns a list of complete messages
#' list(headers = <list>, payload = <raw>); CRC failures raise an error.
es_decoder_new <- function() {
  buf <- raw(0)
  feed <- function(chunk) {
    buf <<- c(buf, chunk); out <- list()
    repeat {
      if (length(buf) < 12L) break
      total <- read_u32_be(buf, 1L)
      if (length(buf) < total) break
      hlen <- read_u32_be(buf, 5L)
      if (crc32_raw(buf[1:8]) != read_u32_be(buf, 9L)) stop("eventstream: prelude CRC mismatch")
      if (crc32_raw(buf[1:(total - 4)]) != read_u32_be(buf, total - 3)) stop("eventstream: message CRC mismatch")
      hb <- if (hlen > 0) buf[13:(12 + hlen)] else raw(0)
      pstart <- 13 + hlen; pend <- total - 4
      payload <- if (pend >= pstart) buf[pstart:pend] else raw(0)
      out[[length(out) + 1L]] <- list(headers = es_parse_headers(hb), payload = payload)
      buf <<- if (total < length(buf)) buf[(total + 1):length(buf)] else raw(0)
    }
    out
  }
  list(feed = feed, pending = function() length(buf))
}
```
Note for porting: the 2-/8-byte header branches mutate `i` inside `switch()` braces; that works in R because the
assignments happen in the function frame. The type-5/8 branches are not exercised by `es_encode`.
**Verifier finding (defect, fix when porting):** the Smithy spec defines header types 2/3/4/5 as *signed* integers, but
`es_parse_headers()` decodes them as unsigned (a hand-built header block decoded byte `0xC8` as `200`, not `-56`). Apply
two's-complement conversion (e.g. `if (v >= 2^(8*k-1)) v - 2^(8*k)` for a k-byte value). Types 2-5, 8 and 9 otherwise parsed
correctly in that test. Bedrock's own headers are strings (type 7), so this does not affect ConverseStream decoding today.

Test (`SCR/v2/test_eventstream.R`: ten ConverseStream-shaped messages including an exception, fed in 7-byte chunks,
plus a corrupted byte). Output:
```
crc32('123456789') = cbf43926 (check value cbf43926)
pure-R crc32 == digest crc32 on 5000 random bytes: TRUE
encoded stream bytes: 1517
decoded messages: 10  leftover bytes: 0
  event     messageStart         {"role":"assistant"}
  event     contentBlockDelta    {"contentBlockIndex":0,"delta":{"text":"Hello, wörld "}}
  event     contentBlockDelta    {"contentBlockIndex":0,"delta":{"text":"<e4><bd><a0><e5><a5><bd>"}}
  event     contentBlockStop     {"contentBlockIndex":0}
  event     contentBlockStart    {"contentBlockIndex":1,"start":{"toolUse":{"toolUseId":"tooluse_1","name":"r_eval"}}}
  event     contentBlockDelta    {"contentBlockIndex":1,"delta":{"toolUse":{"input":"{\"code\":\"1+1\"}"}}}
  event     contentBlockStop     {"contentBlockIndex":1}
  event     messageStop          {"stopReason":"tool_use"}
  event     metadata             {"usage":{"inputTokens":12,"outputTokens":7,"totalTokens":19},"metrics":{"latencyMs":321}}
  exception throttlingException  {"message":"Too many requests"}
reassembled text: Hello, w<U+00F6>rld <e4><bd><a0><e5><a5><bd>  valid UTF-8: TRUE
corrupted byte -> eventstream: message CRC mismatch
throughput: 191 KB/s (pure-R CRC is the bottleneck)
```
(The `<e4>...` rendering is the C-locale printout of a correctly UTF-8 encoded payload; `validUTF8` is TRUE. The Bedrock
payload JSON shapes above are modelled on the ConverseStream reference, not captured from AWS.)

### 5.5 Model reference resolver on the real models.dev catalog

`SCR/v2/model_ref.R` is 246 lines: a first version, plus appended "v2 refinements" that redefine `match_pattern()` and
`gptr_resolve_model()` and add `norm_id()`, `add_owner()`, `break_tie()` and `lossy_alternatives()`. The effective code is below.
This exact block was extracted from this report and re-run (`SCR/v2/check_model_ref_block.R`); it reproduced every run-2 result shown further down.
The other six code blocks in section 5 were checked line-by-line against the scratch files (`SCR/v2/check_report.R`: all identical).
```r
`%||%` <- function(x, y) if (is.null(x)) y else x
THINKING_LEVELS <- c("off", "minimal", "low", "medium", "high", "xhigh", "max")

catalog_from_modelsdev <- function(x, providers = NULL, tool_call_only = TRUE) {
  rows <- list()
  for (pid in names(x)) {
    if (!is.null(providers) && !pid %in% providers) next
    p <- x[[pid]]
    for (m in p$models) {
      if (tool_call_only && !isTRUE(m$tool_call) && !identical(m$type, "decision")) next
      rows[[length(rows) + 1L]] <- data.frame(
        provider = pid, id = m$id, name = m$name %||% m$id, family = m$family %||% NA_character_,
        release_date = m$release_date %||% NA_character_, status = m$status %||% "",
        reasoning = isTRUE(m$reasoning), tool_call = isTRUE(m$tool_call),
        type = m$type %||% "chat", stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, rows)
}

# NSE capture: list(text=, lossy=)
model_expr_text <- function(expr, env = parent.frame()) {
  if (is.character(expr)) return(list(text = expr, lossy = FALSE, from = "string"))
  if (is.symbol(expr)) {
    nm <- as.character(expr)
    if (exists(nm, envir = env, inherits = TRUE)) {           # a bound variable wins
      val <- get(nm, envir = env, inherits = TRUE)
      if (is.character(val) && length(val) == 1L) return(list(text = val, lossy = FALSE, from = "variable"))
      if (inherits(val, "gptr_model")) return(list(text = val$ref, lossy = FALSE, from = "variable"))
    }
    return(list(text = nm, lossy = FALSE, from = "symbol"))
  }
  if (is.call(expr)) {
    ok_ops <- c("/", "-", ":", "::")
    lossy <- FALSE
    walk <- function(e) {
      if (is.call(e)) { if (!as.character(e[[1]]) %in% ok_ops) stop("unsupported model expression: ", deparse(e)); lapply(as.list(e)[-1], walk) }
      else if (is.numeric(e) && (e != trunc(e) || abs(e) >= 1e15)) lossy <<- TRUE
      invisible()
    }
    walk(expr)
    txt <- gsub("[[:space:]]", "", paste(deparse(expr, width.cutoff = 500L), collapse = ""))
    return(list(text = txt, lossy = lossy, from = "call"))
  }
  stop("cannot interpret model reference of type ", typeof(expr))
}

default_aliases <- list(
  sonnet = list(provider = "anthropic", family = "claude-sonnet"),
  opus   = list(provider = "anthropic", family = "claude-opus"),
  haiku  = list(provider = "anthropic", family = "claude-haiku"),
  gemini = list(provider = "google", id = "gemini-flash-latest"),
  flash  = list(provider = "google", id = "gemini-flash-latest"),
  gpt    = list(provider = "openai", family = NULL, pattern = "^gpt-[0-9.]+-sol$"),
  jev    = list(provider = "typesafe", id = "jev-latest", type = "decision"))

resolve_alias <- function(alias, cat) {
  a <- default_aliases[[alias]]; if (is.null(a)) return(NULL)
  c1 <- cat[cat$provider == a$provider & cat$status != "deprecated", ]
  if (!is.null(a$id)) c1 <- c1[c1$id == a$id, ]
  if (!is.null(a$family)) c1 <- c1[!is.na(c1$family) & c1$family == a$family, ]
  if (!is.null(a$pattern)) c1 <- c1[grepl(a$pattern, c1$id), ]
  if (!nrow(c1)) return(NULL)
  c1 <- c1[order(c1$release_date, decreasing = TRUE), ]
  c1[1, ]
}

is_alias_id <- function(id) endsWith(id, "-latest") || !grepl("-\\d{8}$", id)   # Pi isAlias()

norm_id <- function(s) gsub("[._]", "-", tolower(s))           # "claude-sonnet-5.5" == "claude-sonnet-5-5"

# owner of a model = provider part of models.dev canonical_model_id (e.g. "anthropic/claude-opus-5-5")
add_owner <- function(cat, x) {
  own <- character(nrow(cat))
  for (i in seq_len(nrow(cat))) {
    m <- x[[cat$provider[i]]]$models[[cat$id[i]]]
    cm <- if (!is.null(m)) m$canonical_model_id else NULL
    own[i] <- if (is.null(cm)) NA_character_ else sub("/.*$", "", cm)
  }
  cat$owner <- own; cat
}

break_tie <- function(rows, authenticated = NULL) {
  if (!is.null(authenticated)) { a <- rows[rows$provider %in% authenticated, ]; if (nrow(a) == 1L) return(a) ; if (nrow(a)) rows <- a }
  own <- rows[!is.na(rows$owner) & rows$provider == rows$owner, ]
  if (nrow(own) == 1L) return(own)
  NULL
}

match_pattern <- function(pat, cat, authenticated = NULL) {
  lp <- tolower(pat)
  canon <- cat[tolower(paste0(cat$provider, "/", cat$id)) == lp, ]
  if (nrow(canon) == 1L) return(list(model = canon, how = "exact provider/id"))
  sl <- regexpr("/", pat, fixed = TRUE)
  if (sl > 0) {
    pv <- tolower(substr(pat, 1, sl - 1)); rest <- substr(pat, sl + 1, nchar(pat))
    if (pv %in% tolower(cat$provider)) {
      r <- match_pattern(rest, cat[tolower(cat$provider) == pv, ], authenticated)
      if (!is.null(r$model)) return(list(model = r$model, how = paste0(pv, " + ", r$how)))
      return(list(model = NULL, how = "unknown id for known provider", provider = pv, id = rest))
    }
  }
  for (key in c("exact", "normalized")) {
    ex <- if (key == "exact") cat[tolower(cat$id) == lp, ] else cat[norm_id(cat$id) == norm_id(pat), ]
    if (nrow(ex) == 1L) return(list(model = ex, how = paste(key, "id")))
    if (nrow(ex) > 1L) {
      t <- break_tie(ex, authenticated)
      if (!is.null(t)) return(list(model = t, how = paste(key, "id; tie broken by", if (!is.null(authenticated) && t$provider %in% authenticated) "auth" else "owner")))
      return(list(model = NULL, how = "ambiguous", candidates = paste0(ex$provider, "/", ex$id)))
    }
  }
  al <- resolve_alias(lp, cat)
  if (!is.null(al)) return(list(model = al, how = "alias"))
  fam <- cat[!is.na(cat$family) & tolower(cat$family) == lp & cat$status != "deprecated", ]
  if (nrow(fam)) { fam <- fam[order(fam$release_date, decreasing = TRUE), ]
                   o <- fam[!is.na(fam$owner) & fam$provider == fam$owner, ]; if (nrow(o)) fam <- o
                   return(list(model = fam[1, ], how = "family (newest release)")) }
  part <- cat[grepl(lp, tolower(cat$id), fixed = TRUE) | grepl(lp, tolower(cat$name), fixed = TRUE), ]
  if (nrow(part)) {
    pref <- part[vapply(part$id, is_alias_id, TRUE), ]
    pick <- if (nrow(pref)) pref[order(pref$id, decreasing = TRUE), ][1, ] else part[order(part$id, decreasing = TRUE), ][1, ]
    return(list(model = pick, how = sprintf("substring (%d candidates)", nrow(part))))
  }
  list(model = NULL, how = "no match")
}

lossy_alternatives <- function(text, cat) {
  hits <- gregexpr("[0-9]+\\.[0-9]+", text)[[1]]
  if (hits[1] < 0) return(character(0))
  alts <- character(0)
  for (k in seq_along(hits)) {
    num <- regmatches(text, hits)[[1]][k]
    for (z in c("0", "00")) alts <- c(alts, sub(num, paste0(num, z), text, fixed = TRUE))
  }
  ids <- c(paste0(cat$provider, "/", cat$id), cat$id)
  intersect(tolower(alts), tolower(ids))
}

gptr_resolve_model <- function(ref, cat, env = parent.frame(), authenticated = NULL) {
  cap <- if (is.character(ref)) list(text = ref, lossy = FALSE, from = "string") else ref
  pat <- cap$text; thinking <- NULL
  if (isTRUE(cap$lossy)) {
    alt <- lossy_alternatives(pat, cat)
    if (length(alt)) return(structure(list(ok = FALSE, input = pat, how = "bare name lost precision",
      candidates = alt, suggestions = sprintf("quote it: \"%s\" or \"%s\"", pat, alt[1])), class = "gptr_model_ref"))
    cap$lossy <- FALSE
  }
  r <- match_pattern(pat, cat, authenticated)
  if (is.null(r$model) && grepl(":", pat)) {
    lc <- max(gregexpr(":", pat, fixed = TRUE)[[1]]); suf <- substr(pat, lc + 1, nchar(pat))
    if (suf %in% THINKING_LEVELS) { thinking <- suf; r <- match_pattern(substr(pat, 1, lc - 1), cat, authenticated) }
  }
  if (is.null(r$model)) {
    all_ids <- unique(c(paste0(cat$provider, "/", cat$id), cat$id, names(default_aliases)))
    d <- utils::adist(tolower(sub(":.*$", "", pat)), tolower(all_ids))[1, ]
    return(structure(list(ok = FALSE, input = pat, how = r$how, candidates = r$candidates, suggestions = all_ids[order(d)][1:3],
                          fallback = if (!is.null(r$provider)) sprintf("%s/%s (custom id, default capabilities)", r$provider, r$id)),
                     class = "gptr_model_ref"))
  }
  structure(list(ok = TRUE, input = pat, provider = r$model$provider, id = r$model$id, thinking = thinking, how = r$how,
                 lossy = FALSE, ref = paste0(r$model$provider, "/", r$model$id, if (!is.null(thinking)) paste0(":", thinking) else "")),
            class = c("gptr_model", "gptr_model_ref"))
}

print.gptr_model_ref <- function(x, ...) {
  if (isTRUE(x$ok)) cat(sprintf("%-34s -> %-44s [%s]%s\n", x$input, x$ref, x$how,
                                if (isTRUE(x$lossy)) "  WARNING: numeric literal in bare name; quote the id" else ""))
  else cat(sprintf("%-34s -> NOT RESOLVED [%s]%s%s did you mean: %s\n", x$input, x$how,
                   if (!is.null(x$candidates)) paste0(" ambiguous: ", paste(head(x$candidates, 4), collapse = ", ")) else "",
                   if (!is.null(x$fallback)) paste0(" fallback: ", x$fallback) else "",
                   paste(x$suggestions, collapse = ", ")))
  invisible(x)
}

model_arg <- function(model, cat) {        # NSE front door as gptr() would use it
  cap <- model_expr_text(substitute(model), parent.frame())
  gptr_resolve_model(cap, cat)
}
```
Run 1 (`test_model_ref.R`, first version without owner/normalisation; 17 providers + a synthetic `typesafe/jev-latest` row from the
decision endpoint + two synthetic `ollama` rows standing in for live discovery), excerpt:
```
catalog rows: 894 providers: 19
anthropic/claude-sonnet-5-5        -> anthropic/claude-sonnet-5-5                  [exact provider/id]
claude-opus-5-5:xhigh              -> NOT RESOLVED [ambiguous] ambiguous: anthropic/claude-opus-5-5, azure/claude-opus-5-5 did you mean: ...
sonnet                             -> anthropic/claude-sonnet-5-5                  [alias]
opus:high                          -> anthropic/claude-opus-5-5:high               [alias]
haiku                              -> anthropic/claude-haiku-4-5                   [alias]
jev                                -> typesafe/jev-latest                          [alias]
gemini                             -> google/gemini-flash-latest                   [alias]
google/gemini-3.8-flash:low        -> google/gemini-3.8-flash:low                  [exact provider/id]
gpt                                -> openai/gpt-6.1-sol                           [alias]
gpt-6-sol                          -> NOT RESOLVED [ambiguous] ambiguous: azure/gpt-6-sol, github-copilot/gpt-6-sol, openai/gpt-6-sol ...
ollama/llama3.2:3b                 -> ollama/llama3.2:3b                           [exact provider/id]
ollama/qwen3.5:9b:high             -> ollama/qwen3.5:9b:high                       [exact provider/id]
ollama/mistral-nemo                -> NOT RESOLVED [unknown id for known provider] fallback: ollama/mistral-nemo (custom id, default capabilities) ...
claude-sonet-5-5                   -> NOT RESOLVED [no match] did you mean: claude-sonnet-5-5, claude-sonnet-4-5, claude-sonnet-5.5
gpt-oss-120b                       -> cerebras/gpt-oss-120b                        [exact id]
sonnet:turbo                       -> NOT RESOLVED [no match] did you mean: sonnet, o1, o3
claude-sonnet                      -> anthropic/claude-sonnet-5-5                  [family (newest release)]
-- NSE forms --
anthropic/claude-sonnet-5-5        -> anthropic/claude-sonnet-5-5                  [exact provider/id]
opus:high                          -> anthropic/claude-opus-5-5:high               [alias]
groq/openai/gpt-oss-120b           -> groq/openai/gpt-oss-120b                     [exact provider/id]   (bound variable my_model)
worst-case (fuzzy + adist) resolution: 9.6 ms per call over 894 rows
```
(Verifier re-run with the effective code below, same 894 rows: exact/alias refs 7.5-9.7 ms, no-match refs about 15 ms per call,
one measurement of 60 ms/call on the no-match path. The 9.6 ms figure applies to the first version only; either way it is fine for
interactive use but should not sit in a hot loop.)
Run 2 (`test_model_ref2.R`, effective code above, `add_owner()` applied; 587 of 894 rows have an owner):
```
claude-opus-5-5:xhigh              -> anthropic/claude-opus-5-5:xhigh              [exact id; tie broken by owner]
gpt-6-sol                          -> openai/gpt-6-sol                             [exact id; tie broken by owner]
deepseek-v4-pro                    -> deepseek/deepseek-v4-pro                     [exact id; tie broken by owner]
kimi-k3                            -> NOT RESOLVED [ambiguous] ambiguous: ollama-cloud/kimi-k3, github-copilot/kimi-k3 ...
openrouter/anthropic/claude-sonnet-5-5 -> openrouter/anthropic/claude-sonnet-5.5       [openrouter + normalized id]
openrouter/claude-sonnet-5.5       -> openrouter/anthropic/claude-sonnet-5.5       [openrouter + substring (1 candidates)]
claude-sonet-5-5                   -> NOT RESOLVED [no match] did you mean: claude-sonnet-5-5, claude-sonnet-4-5, claude-sonnet-5.5
ollama/qwen3.5:9b:high             -> ollama/qwen3.5:9b:high                       [exact provider/id]
with authenticated = c('azure'):
claude-opus-5-5                    -> azure/claude-opus-5-5                        [exact id; tie broken by auth]
-- NSE --
google/gemini-3.8-flash            -> google/gemini-3.8-flash                      [exact provider/id]
openai/gpt-5.1                     -> openai/gpt-5.1                               [exact provider/id]
gpt-6-sol:high                     -> openai/gpt-6-sol:high                        [exact id; tie broken by owner]
```
Reading: `openai/gpt-5.10` typed bare silently became `openai/gpt-5.1`, because no `gpt-5.10` exists in the catalog to trigger the
lossy check. Hence rule 3 in 4.9: *always print the resolution of bare calls containing decimals*. `kimi-k3` stays ambiguous (no
owner in this subset), which is correct. Bare `sonnet:turbo` is rejected rather than silently dropping the bad suffix, matching
Pi's strict CLI mode.

### 5.6 Catalog snapshot sizing and endpoint probes

`SCR/v2/catalog_snapshot.R` (prunes the downloaded api.json to 25 providers; writes JSON, json.gz, json.xz, rds) output:
```
snapshot: 25 providers, 1227 models (tool-capable, non-deprecated, text out)
    openrouter         vercel amazon-bedrock    huggingface          azure
           320            238            170             76             61
     deepinfra         openai  google-vertex github-copilot   ollama-cloud
            59             34             34             34             24
       mistral         nvidia   fireworks-ai         google     togetherai
            23             23             22             21             20
           zai      anthropic         cohere           groq            xai
            18             16              9              7              7
    moonshotai       lmstudio       cerebras       deepseek     perplexity
             4              3              2              2              0

full api.json          :   5140.5 KB
full api.json.gz       :    512.9 KB
pruned json            :    664.4 KB
pruned json.gz         :     51.3 KB
pruned json.xz         :     34.2 KB
pruned rds (xz)        :     44.8 KB
load time: json.gz + jsonlite 0.051 s | rds 0.045 s

tools::R_user_dir('gptr', 'cache') = /Users/wanjun/Library/Caches/org.R-project.R/R/gptr
tools::R_user_dir('gptr', 'config') = /Users/wanjun/Library/Preferences/org.R-project.R/R/gptr
tools::R_user_dir('gptr', 'data') = /Users/wanjun/Library/Application Support/org.R-project.R/R/gptr
```
(Pruning to tool-capable models drops e.g. Perplexity to 0; the real build script should keep Perplexity if wanted.)

`SCR/fetch_modelsdev.R` and `SCR/v2/probe_endpoints.R` outputs:
```
status: 200
bytes: 5263829
[1] "content-type: application/json"  "access-control-allow-origin: *"  "cache-control: public, max-age=0, must-revalidate"
[4] "etag: W/\"a174062643509bd51dc6338a3e8bb26a\""  "content-encoding: gzip"
n providers: 225
n models: 8323

== https://models.dev/models.json status 200 bytes 402067 type application/json      (434 entries, keyed "bytedance-seed/seed-2.0-pro", ...)
== https://models.dev/catalog.json status 200 bytes 5665920 type application/json     (top-level: providers, models)
== https://models.dev/models.json?type=decision status 200 bytes 450 type application/json
{ "typesafe/jev-latest": { "id": "typesafe/jev-latest", "type": "decision", "name": "Jev",
    "description": "System One model for fast, typed probabilistic decisions over text or structured state",
    "attachment": false, "reasoning": false, "tool_call": false, "structured_output": true, "temperature": false,
    "release_date": "2026-09-15", "last_updated": "2026-09-15", "modalities": { "input": ["text"], "output": ["text"] },
    "open_weights": false, "limit": { "context": 64000, "output": 0 } } }

conditional GET with etag W/"a174062643509bd51dc6338a3e8bb26a" -> status 304 bytes 0
```
The field census in 3.8 is the output of `SCR/analyze_modelsdev.R`; the Google/Anthropic/OpenAI tables in 2.1/2.9 come from
`SCR/analyze3.R` (e.g. `gemini-3.8-flash 2026-09-02 ctx 1048576 out 65536 $0.75/$3.75 effort[low|medium|high]`,
`claude-sonnet-5-5 2026-09-28 ctx 1000000 out 128000 $2/$10 effort[low|medium|high|xhigh|max]`,
`gpt-6.1-sol 2026-09-29 ctx 1050000 out 128000 $2/$10 effort[low|medium|high|xhigh|max]`).

### 5.7 NSE deparse experiment (executed)

```r
f <- function(model) { e <- substitute(model); list(class = class(e)[1], deparsed = paste(deparse(e), collapse=""),
                                                    stripped = gsub("[[:space:]]", "", paste(deparse(e), collapse=""))) }
```
```
sonnet                           -> name   sonnet                                   sonnet
anthropic/claude-sonnet-5-5      -> call   anthropic/claude - sonnet - 5 - 5        anthropic/claude-sonnet-5-5
openai/gpt-5.10                  -> call   openai/gpt - 5.1                         openai/gpt-5.1
google/gemini-3.8-flash          -> call   google/gemini - 3.8 - flash              google/gemini-3.8-flash
sonnet:high                      -> call   sonnet:high                              sonnet:high
ollama/llama3                    -> call   ollama/llama3                            ollama/llama3
gpt-6-sol                        -> call   gpt - 6 - sol                            gpt-6-sol
`ollama/qwen3.5:397b`            -> name   ollama/qwen3.5:397b                      ollama/qwen3.5:397b
deepseek/deepseek-v4-pro         -> call   deepseek/deepseek - v4 - pro             deepseek/deepseek-v4-pro
groq/openai/gpt-oss-120b         -> PARSE ERROR <text>:1:26: unexpected symbol
x/gemma4:31b                     -> PARSE ERROR <text>:1:14: unexpected symbol
a/b-1e3                          -> call   a/b - 1000                               a/b-1000
claude-opus-5-5:xhigh            -> call   claude - opus - 5 - 5:xhigh              claude-opus-5-5:xhigh
```

### 5.8 What I could not run

- No real calls to Gemini, OpenRouter, Groq, Azure, Bedrock, Copilot or local servers (no keys used, no paid calls, no local
  Ollama/llama.cpp/vLLM installed). All wire formats come from official docs + Pi source, and the parsers were exercised against mocks.
- Exact Gemini SSE line terminators (`\r\n\r\n` vs `\n\n`) were not observed on the wire; the parser accepts both.
- Windows was not tested (see 6).

---

## 6. CRAN and cross-platform considerations

- **No network in examples/tests/vignettes.** Parsers (SSE, eventstream, SigV4, catalog merge, model resolver) must be unit-tested
  from fixtures and the AWS vectors, which is fully offline. Socket-based mock-server tests (5.1) need `processx`/`callr` and a free
  port: keep them, but `skip_on_cran()` them (local sockets are allowed by CRAN, but they are flaky on shared check machines and
  need a background process). Use at most 2 processes (CRAN core limit).
- **Internet failures must be graceful** ("fail gracefully with an informative message ... and not give a check warning nor error"):
  `gptr_models_update()` must `tryCatch` network errors and keep the snapshot; discovery of local servers uses ≤ 1 s timeouts and
  never runs at load time.
- **File writes**: only `tools::R_user_dir("gptr", "cache"|"config"|"data")` (R ≥ 4.0, so `Depends: R (>= 4.0)`; 4.1 if `|>` is used
  in package code), only on explicit user action, kept small, and old files pruned. The snapshot in `inst/extdata` (≈ 50 KB) is far
  below the 5 MB data guideline. Include the models.dev MIT notice.
- **Encoding**: keep all R sources ASCII (the Write-tool episode in this track shows how easily literals turn into raw UTF-8). Build
  test strings with `intToUtf8()`. Decode network bytes with `rawToChar()` + `Encoding<- "UTF-8"` and never `iconv` from native.
  Verified correct in a C locale. On Windows R ≥ 4.2 (UCRT) the native encoding is UTF-8, so console printing of non-ASCII model
  output also works; on older Windows R it prints `<U+...>` escapes but data stays correct.
- **Windows specifics**:
  - curl on Windows uses Schannel and the Windows certificate store; corporate proxies via `HTTPS_PROXY`/`NO_PROXY`
    (`curl::ie_get_proxy_for_url()` can read the system proxy).
  - The Windows CRAN build of the curl package bundles its own libcurl, so `aws_sigv4` is LIKELY present, but check
    `"aws_sigv4" %in% names(curl::curl_options())` at run time and fall back to pure R.
  - `Rscript.exe` path for test servers: `file.path(R.home("bin"), "Rscript.exe")`, as in the prototypes.
  - `localhost` may resolve to `::1` first on Windows while Ollama/llama.cpp listen on `127.0.0.1`: default local base URLs to
    `http://127.0.0.1:<port>` rather than `localhost` (LIKELY issue; the docs themselves mix both).
  - Interrupts: the curl-multi loop returns to R every 50 ms, so Esc/Ctrl-C in RGui/RStudio is delivered; a blocking read would not be interruptible.
- **Locale-independent formatting**: `format(..., tz = "UTC")` for `x-amz-date` (verified); never rely on `Sys.setlocale`.
- **Time skew**: SigV4 rejects requests with > 5 min clock skew (AWS behaviour, LIKELY); surface `RequestTimeTooSkewed` clearly.

---

## 7. Risks, pitfalls, open questions

Risks and pitfalls (observed or documented):
1. **Gemini thought signatures**: any history editing (compaction, the "script is history" rewriting of REQ-26) that drops or moves
   a signed part within the current turn breaks Gemini 3 function calling with HTTP 400. The session format must store signatures
   per block, and compaction must only cut *before* the current turn.
2. **Gemini thinking-level errors**: sending `thinkingLevel: MINIMAL` to 3.8/3.7 Flash is an error, and `thinkingConfig` on a
   non-thinking model is an error ("An error will be returned if this field is set for models that don't support thinking").
   Always clamp against the catalog and omit `thinkingConfig` for `reasoning == FALSE` models.
3. **Unknown enum values** (new FinishReason values appear often): default to `error` with the raw value preserved.
4. **Stale catalog**: the shipped snapshot ages between CRAN releases (months). Mitigations: user refresh, the `allow_unknown`
   fallback for known providers, and live `/v1/models` discovery for local servers. Unlike Pi, gptr has no always-on remote overlay.
5. **Aggregator ID drift**: the same model has different IDs per provider (`claude-sonnet-5-5` vs OpenRouter `anthropic/claude-sonnet-5.5`
   vs Copilot `claude-sonnet-5.5`); normalised matching helps but can produce false positives. Only apply it within one provider or to
   exact normalised equality, as prototyped (never substring on normalised IDs).
6. **Compat flags are "verified differences"**: Pi warns not to guess them. gptr's generic `openai_compatible()` should start from
   *conservative* defaults (no `store`, `system` role, `max_tokens`, no strict, no `stream_options` only if the server rejects it)
   and let users opt in. The auto-detection table (3.3) is URL-based and must be kept in sync with Pi.
7. **`[DONE]` is not universal and `finish_reason` may be absent** (some local servers): expose `supports_finish_reason = FALSE` for local
   profiles, or treat a clean EOF after content as `stop`. Pi's strict default would report local streams as errors.
8. **Reasoning replay semantics diverge**: DeepSeek (required with tools), Cerebras/Together (same field), OpenRouter (`reasoning_details`),
   Gemini (signatures), vLLM/llama.cpp (template-dependent). Store thinking with its origin `{provider, model, field, signature, details}`
   and replay only to the same provider+model; otherwise convert to text or drop (Pi's `transformMessages`).
9. **`<think>` tags in content** for some servers/models need a streaming splitter, which Pi does not have; it is a new component for gptr.
10. **Bedrock OpenAI endpoint coverage is model-dependent** (e.g. gpt-oss supports Chat Completions but not Responses on bedrock-runtime).
    Claude on Bedrock still needs Converse or the Messages API page (not researched in depth here: open question).
11. **SigV4 correctness against real AWS** is only indirectly verified (AWS vectors + libcurl parity). A live smoke test by the maintainer
    is needed before release; session tokens (`x-amz-security-token` signed) are implemented but not exercised against libcurl.
12. **Copilot and subscription-style access** carry ToS risk; keep them out of core.
13. **NSE pitfalls**: lossy decimals, parse errors for IDs containing digit-letter tokens, and variables shadowing aliases. Document and
    print resolutions; the history file always gets quoted IDs.
14. **httr2 blocking SSE**: if another track reuses ellmer or httr2 `resp_stream_sse()` blindly, streaming will look laggy. Fix: 4.4.

Open questions:
- Gemini: will gptr adopt the Interactions API (server-side state conflicts with "script is history" and privacy; `store=false` exists)?
  Proposed answer: not before a needed feature is Interactions-only.
- Gemini via Vertex AI (ADC/service-account OAuth2 JWT signing in R, possible with openssl): scope for a later track.
- Should local servers default to `127.0.0.1` or `localhost`? Needs a Windows check.
- Should gptr honour `GOOGLE_API_KEY` precedence over `GEMINI_API_KEY` like Google's SDKs (conflicts with Pi)? Proposed: `GEMINI_API_KEY` first
  (it is Gemini-specific), then `GOOGLE_API_KEY`, and warn if both are set with different values.
- Does Ollama's OpenAI-compatible stream always use `delta.reasoning` (vs `reasoning_content`)? The three-field rule makes this moot for
  parsing, but replay should reuse the observed field.
- Bedrock "Messages API" (Anthropic-compatible) page: if it accepts API keys, Claude on Bedrock could reuse the Anthropic adapter.
- Exact exception-type strings in Bedrock ConverseStream event streams, and whether payloads contain padding fields: needs a live capture.

---

## 8. Sources

Local (Pi clone, commit 1b347794; `PI/` = `.../scratchpad/pi/packages/`):
- `PI/ai/src/types.ts:767-1019` (events, `OpenAICompletionsCompat`, other compat interfaces, OpenRouter routing); `BaseModel`/`Model` interfaces.
- `PI/ai/src/api/openai-completions.ts` (lines cited throughout: 299-729 stream, 752-795 client/headers, 797-1002 params, 1185-1472 messages,
  1474-1509 tools, 1511-1552 usage, 1554-1578 stop reasons, 1585-1726 detect/getCompat).
- `PI/ai/src/api/google-generative-ai.ts` (1-471), `PI/ai/src/api/google-shared.ts` (1-515).
- `PI/ai/src/api/azure-openai-responses.ts` (25-51, 191-278); `PI/ai/src/providers/azure-openai-responses.ts`.
- `PI/ai/src/api/bedrock-converse-stream.ts` (80-239); `PI/ai/src/providers/amazon-bedrock.ts`.
- `PI/ai/src/api/mistral-conversations.ts` (28-45, 196-215, 259-267, 303-356).
- `PI/ai/src/api/github-copilot-headers.ts`; `PI/ai/src/auth/oauth/github-copilot.ts` (58-86, 174-344); `PI/ai/src/providers/github-copilot.ts`.
- `PI/ai/src/api/llama-cpp-classify.ts` (16-35 and label logic); `PI/coding-agent/src/extensions/llama/provider.ts` (23, 100-130), `client.ts` (176-232).
- `PI/ai/src/providers/{groq,cerebras,xai,deepseek,mistral,together,fireworks,huggingface,openrouter,google}.ts`.
- `PI/ai/src/env-api-keys.ts` (68-121); `PI/ai/src/models.ts` (1193-1249); `PI/ai/src/compat.ts` (legacy API entrypoint, not the flags).
- `PI/ai/scripts/generate-models.ts` (166-241, 471-473, 529-570, 905-970, 1016-1160, 1280-1368, 1592-1754, 1756-2393, 3071-3113);
  `PI/ai/scripts/models-dev-reasoning-options.ts` (1-30).
- `PI/coding-agent/src/core/model-resolver.ts` (20-257, 406-606); `PI/coding-agent/src/cli/args.ts:60-63`;
  `PI/coding-agent/src/core/model-config.ts` (11-253); `PI/coding-agent/src/core/remote-catalog-provider.ts:15`.
- `PI/coding-agent/docs/models.md`, `custom-provider.md`, `llama-cpp.md`, `providers.md`.
- ellmer 0.4.0 installed sources (printed): `chat_perform_stream`, `chat_perform_async_stream`, `ProviderGoogleGemini` methods; httr2 1.2.2
  `resp_stream_sse`, `resp_boundary_pushback`, `parse_event`.

Web (fetched 2026-09-29; copies in `SCR/web/` unless marked live):
- Gemini: https://ai.google.dev/api/generate-content ; https://ai.google.dev/api/caching ; https://ai.google.dev/api/models ;
  https://ai.google.dev/api/interactions-api ; https://ai.google.dev/gemini-api/docs/models (also live) ;
  https://ai.google.dev/gemini-api/docs/generate-content/thinking (also live) ; https://ai.google.dev/gemini-api/docs/generate-content/thought-signatures ;
  https://ai.google.dev/gemini-api/docs/generate-content/function-calling ; https://ai.google.dev/gemini-api/docs/generate-content/text-generation ;
  https://ai.google.dev/gemini-api/docs/generate-content/image-understanding ; https://ai.google.dev/gemini-api/docs/api-key ;
  https://ai.google.dev/gemini-api/docs/openai ; https://ai.google.dev/gemini-api/docs/interactions-overview ;
  https://ai.google.dev/gemini-api/docs/migrate-to-interactions ; https://ai.google.dev/gemini-api/docs/deprecations ;
  https://ai.google.dev/gemini-api/docs/rate-limits ; https://ai.google.dev/gemini-api/docs/troubleshooting ; https://ai.google.dev/gemini-api/docs/changelog
- OpenRouter: https://openrouter.ai/docs/llms.txt and pages app-attribution, errors, overview, reasoning-tokens, streaming, usage-accounting.
- Groq: https://console.groq.com/docs/openai ; https://console.groq.com/docs/reasoning (live).
- Cerebras: https://inference-docs.cerebras.ai/llms.txt ; https://inference-docs.cerebras.ai/capabilities/reasoning.md (live) ;
  https://inference-docs.cerebras.ai/resources/openai.md (live).
- xAI: https://docs.x.ai/llms.txt ; https://docs.x.ai/developers/model-capabilities/text/reasoning (live).
- DeepSeek: https://api-docs.deepseek.com/guides/thinking_mode (live).
- Mistral: https://docs.mistral.ai/llms.txt ; https://docs.mistral.ai/api/endpoint/chat (live).
- Together: https://docs.together.ai/llms.txt ; https://docs.together.ai/docs/inference/openai-compatibility.md (live) ;
  https://docs.together.ai/docs/inference/chat/reasoning.md (live).
- Fireworks: https://docs.fireworks.ai/llms.txt ; Hugging Face: https://huggingface.co/docs/inference-providers (router page).
- Ollama: https://docs.ollama.com/api/openai-compatibility ; https://github.com/ollama/ollama/blob/main/docs/api.md ;
  web search result summarising https://github.com/ollama/ollama/issues/14820 and https://docs.ollama.com/capabilities/thinking.
- LM Studio: https://lmstudio.ai/docs/developer/openai-compat ; llama.cpp: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md ;
  vLLM: https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html , https://docs.vllm.ai/en/latest/features/reasoning_outputs.html ,
  https://docs.vllm.ai/en/latest/features/tool_calling.html
- Azure: https://learn.microsoft.com/en-us/azure/ai-foundry/openai/api-version-lifecycle (v1 API page; now 301-redirects to
  https://learn.microsoft.com/en-us/azure/foundry/openai/api-version-lifecycle, the canonical URL).
- AWS: https://docs.aws.amazon.com/bedrock/latest/userguide/api-keys-use.html ; https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseStream.html ;
  https://docs.aws.amazon.com/bedrock/latest/userguide/inference-chat-completions.html (corrected by verifier: the previously
  cited `bedrock-chat-completions.html` does not exist and serves a redirect stub; the saved copy's canonical URL is this one) ; https://docs.aws.amazon.com/IAM/latest/UserGuide/create-signed-request.html ;
  https://smithy.io/2.0/aws/amazon-eventstream.html (live) ;
  https://raw.githubusercontent.com/awslabs/aws-c-auth/main/tests/aws-signing-test-suite/v4/get-vanilla/{context.json,request.txt,header-canonical-request.txt,header-signature.txt} (live) ;
  same for `post-x-www-form-urlencoded` (live);
  web search on the Bedrock colon pitfall: https://github.com/BerriAI/litellm/issues/15788 , https://github.com/yologdev/yoagent/pull/200
- models.dev: https://models.dev/api.json , https://models.dev/models.json , https://models.dev/catalog.json ,
  https://models.dev/models.json?type=decision (all executed) ; https://github.com/sst/models.dev (README, license MIT).
- CRAN policy: https://cran.r-project.org/web/packages/policies.html (live).

---

## Verification log

Independent fact-check, 2026-09-29, same machine (R 4.4.3, locale C, httr2 1.2.2, curl 7.0.0 / libcurl 8.14.1, openssl 2.3.5,
digest 0.6.39, ellmer 0.4.0), Pi clone at `1b34779`. Every R block in section 5 was extracted verbatim from this report (not
from the scratch files) into `.../scratchpad/work/verify-09/v2/` and re-run with `Rscript --vanilla`; all ran without edits.
Web facts were re-fetched live (ai.google.dev `.md.txt` copies, AWS/Microsoft pages via curl, others via WebFetch). No paid API
calls, no credentials used (SigV4 tests use the public `AKIDEXAMPLE` test identity).

| # | Claim (section) | Verdict | Source used |
|---|---|---|---|
| 1 | Gemini endpoints `...:generateContent`, `...:streamGenerateContent?alt=sse`; ellmer adds `alt=sse` (2.1) | confirmed | live `ai.google.dev/api/generate-content.md.txt` (byte-identical to the saved copy); printed `S7::method(chat_request, ProviderGoogleGemini)` |
| 2 | "header `x-goog-api-key` in every REST example" (2.1, 1) | **corrected** | API-reference pages use `?key=$GEMINI_API_KEY` (23 samples, 0 headers); guides use the header. Report now says prefer the header |
| 3 | Request body fields; Candidate/Response/UsageMetadata fields; `thinkingConfig` inside `generationConfig` (2.1) | confirmed | live API reference |
| 4 | FinishReason enum (22 values incl. the 4 newest); Pi maps STOP/MAX_TOKENS, rest error (2.1) | confirmed | live API reference; `google-shared.ts:441-483` |
| 5 | thinkingLevel table, "cannot disable 3.1 Pro", 2.5 budget ranges, `max_output_tokens` includes thoughts, thoughts billed as output (2.1) | confirmed | live thinking guide |
| 6 | `thinkingLevel` on pre-3 models | added | API reference: "Use with earlier models results in an error" |
| 7 | Thought-signature rules (first parallel call only, current-turn validation, 4xx, OpenAI-compat `extra_content.google.thought_signature`) (2.1) | confirmed | live thought-signatures guide |
| 8 | Pi `usesGoogleThinkingLevel` regex, 2.5 budget maps, usage normalisation, "ended without a finish reason" (2.1, 2.2) | confirmed | `google-shared.ts:72-83`, `google-generative-ai.ts:232-251, 276-278, 431-471` |
| 9 | Pi Gemini function-calling mode choice (4.5) | corrected (precision) | `google-shared.ts:404-436`: explicit `none`/`any` win over `VALIDATED`; Pi has no `required` mapping |
| 10 | `OpenAICompletionsCompat` has ~27 flags; defaults, `isNonStandard`, host list, `getCompat` override order (3.3) | confirmed (27 flags) | `types.ts:789-866`, `openai-completions.ts:1585-1726` |
| 11 | `cacheControlFormat` default (3.3) | corrected (precision) | set only when `provider === "openrouter"`, not URL-detected |
| 12 | Reasoning field order `reasoning_content`, `reasoning`, `reasoning_text`; finish-reason map; usage parse; "Stream ended without finish_reason" (2.3) | confirmed | `openai-completions.ts:553-700, 1511-1578` |
| 13 | Thinking request shapes per `thinkingFormat`; default budgets 1024/2048/8192/16384, 1024 answer tokens kept (3.4) | confirmed | `openai-completions.ts:875-1024`; `simple-options.ts:52-58` |
| 14 | "Assistant content is always a plain string, never an array" (2.3) | **corrected** | `openai-completions.ts:1315-1320`: array when `requiresThinkingAsText` |
| 15 | Pi default models per provider; google default at `model-resolver.ts:30` (2.1, 3.5) | confirmed; line fixed to `:29`; Azure key is `azure-openai-responses` | `model-resolver.ts:19-62` |
| 16 | Thinking levels `off..max` (`cli/args.ts:60`), clamp up-then-down, last-colon suffix rule (2.9, 3.9) | confirmed | `cli/args.ts:60`, `models.ts:1215-1249`, `model-resolver.ts:204-257` |
| 17 | Pi catalog: `api.json` fetch `:1759`, `type=decision`, OpenRouter modality lists, 4 h remote overlay with `?types=chat,image,classifier` and ETag (2.8) | confirmed | `generate-models.ts:1311-1312, 1759, 2677`; `remote-catalog-provider.ts:15-22, 104-151` |
| 18 | Copilot device-flow URLs, token exchange, `proxy-ep`, static + dynamic headers, routing regex (2.7, 3.7) | confirmed | `github-copilot.ts:58-86, 217`; `generate-models.ts:166-171, 2336-2395`; `github-copilot-headers.ts` |
| 19 | Azure Pi constants (`"v1"`, min 16 output tokens), env names, base-URL resolution/normalisation (2.5) | confirmed | `azure-openai-responses.ts:25-28, 48, 191-259` |
| 20 | Azure v1: `/openai/v1/` base (also `services.ai.azure.com`), no api-version, `api-key` or Entra Bearer (`https://ai.azure.com/.default`), model = deployment (2.5) | confirmed; source URL now redirects | live MS Learn page (canonical `azure/foundry/...`) |
| 21 | Bedrock OpenAI-compatible endpoint, `bedrock-mantle`, no `GET /models`, gpt-oss not on Responses, guardrail headers/body field (2.6) | confirmed; **source URL corrected** | live `inference-chat-completions.html` (`bedrock-chat-completions.html` is a redirect stub) |
| 22 | Bedrock API keys (`AWS_BEARER_TOKEN_BEDROCK`, Bearer, excluded operations) (2.6) | confirmed | live `api-keys-use.html` |
| 23 | ConverseStream request fields and event union members (2.6) | confirmed | live API reference |
| 24 | Smithy eventstream layout, limits 24 MB / 128 KB, message types (2.6) | confirmed | live smithy.io page |
| 25 | Header integer types (2.6, 5.4) | **corrected** | spec says signed int8/16/32/64; prototype decodes unsigned (defect documented in 5.4) |
| 26 | Pure-R SigV4 matches `get-vanilla` and `post-x-www-form-urlencoded` (5.3) | confirmed (signature and canonical request both identical) | vectors fetched live from `awslabs/aws-c-auth` |
| 27 | Pure-R SigV4 byte-identical to libcurl `aws_sigv4`, incl. `:` and `%3A` model IDs (5.3) | confirmed (3/3 identical, own capture server) | re-run; signatures differ from the report's only because the timestamp differs |
| 28 | SigV4 query canonicalisation (5.3) | limitation found | `x=a=b` → `x=a`; `a%20b` → `a%2520b`; documented under 5.3 |
| 29 | Eventstream codec: CRC check value `cbf43926`, equals `digest` crc32, 7-byte chunk decoding, CRC mismatch detected, ~190 KB/s (5.4) | confirmed (195 KB/s) | re-run of report code |
| 30 | Streaming client 5.1: all scenarios, both transports equivalent, latency table (median 0.25 s vs blocking 0.00 s / max 1.52 s) | confirmed | re-run of `run_stream_tests.R` extracted from the report (20 s) |
| 31 | httr2 blocking read mechanism: 1024-byte reads → first data 1.27-1.30 s; `chunk_size <- min(max_size + 1, 1024)`; `parse_event` sets UTF-8 (2.10, 5.2) | confirmed | re-run; printed `httr2:::resp_boundary_pushback`, `httr2:::parse_event` |
| 32 | ellmer 0.4.0 sync streaming = `req_perform_connection()` (default `blocking = TRUE`) + `resp_stream_sse()`; async uses `blocking = FALSE` + `later::later_fd()` (2.10) | confirmed | printed `ellmer:::chat_perform_stream`, `chat_perform_async_stream`, `chat_resp_stream` method |
| 33 | Model resolver 5.5 results (run 1 and run 2 lines) | confirmed (all lines reproduced on a fresh catalog) | re-run of the report block, own harness |
| 34 | Exec summary 14 tie-break order | **corrected** | code: authenticated provider first, then owner |
| 35 | Resolver timing "9.6 ms per call" | corrected (context) | effective code: 7.5-15 ms, one run 60 ms on no-match |
| 36 | NSE deparse table (5.7); also bare `qwen3.5:9b`, `llama3.2:3b`, `gpt-oss-120b` are parse errors | confirmed | re-run via `str2lang()` |
| 37 | models.dev: 225 providers, 8,323 models, 5,263,829 bytes, field census in 3.8, provider env/api values, no `ollama`/`typesafe` provider, `gemini-flash-latest` carries 3.8's cost/effort | confirmed (every count identical) | fresh download + own census script |
| 38 | models.dev ETag/304; other endpoints (models.json 402,067 B / 434 entries; catalog.json; decision endpoint 450 B, one entry); MIT licence | confirmed; ETag value changed with content | live curl |
| 39 | Snapshot sizing: 25 providers → 1,227 models; ~51 KB gz, ~34 KB xz; ~0.05 s load (4.8, 5.6) | confirmed (1,227 exact; 53.6 KB gz / 34.7 KB xz / 0.085 s with my field choice) | own pruning script |
| 40 | `tools::R_user_dir()` paths on macOS (5.6) | confirmed | re-run |
| 41 | OpenRouter: `HTTP-Referer` required, `X-OpenRouter-Title` (X-Title legacy), usage always included and `include_usage` deprecated no-op, cost in credits, effort values incl. `max`/`xhigh`, pass `reasoning_details` back unmodified | confirmed | live OpenRouter docs |
| 42 | Groq 400 on `logprobs`, `logit_bias`, `top_logprobs`, `messages[].name`; `n` = 1; temp 0 → 1e-8 | confirmed | live Groq docs |
| 43 | DeepSeek thinking: `thinking.type`, effort `low`/`high`/`max`, `reasoning_content`, 400 if not replayed with tools, sampling params ignored | confirmed (wording refined) | live DeepSeek doc |
| 44 | Cerebras: `delta.reasoning`, replay `reasoning`, `clear_thinking`, per-model effort values | confirmed | live Cerebras doc |
| 45 | Ollama OpenAI compat supported/unsupported fields, base64-only images, dummy key | confirmed | live Ollama doc |
| 46 | llama.cpp: `--api-key`/`LLAMA_API_KEY`, `--jinja` default on, `--reasoning-format` semantics, `/health` public, `/v1/messages` | confirmed; `--reasoning-format` wording corrected | live README (master) |
| 47 | Pi llama.cpp extension compat profile and `qwen-chat-template` detection | confirmed | `extensions/llama/provider.ts:98-130` |
| 48 | vLLM `reasoning` renamed from `reasoning_content`, `--reasoning-parser`, `thinking_token_budget` | confirmed | live vLLM doc |
| 49 | HF router suffixes (`:fastest` default, `:cheapest`, `:preferred`, `:<provider>`), `HF_TOKEN` | confirmed | live HF docs |
| 50 | Gemini models page IDs, 2.5 access-limited, shut-down list, "3.5 Flash-Lite or 3.8 Flash" recommendation, 2-week latest-alias notice | confirmed | live models page |
| 51 | Gemini OpenAI-compat base URL, effort mapping, `extra_body.google.thinking_config`, beta status | confirmed | live `/openai` page |
| 52 | Interactions API URL, "legacy but fully supported", new features launch there, stored by default / `store=false`, GA June 2026 | confirmed | live overview page |
| 53 | Gemini API keys: env precedence `GOOGLE_API_KEY` > `GEMINI_API_KEY`; auth keys; unrestricted keys rejected | confirmed; nuance added | live api-key page |
| 54 | CRAN policy quotes (graceful Internet failure, 5 MB, 2 cores, `R_user_dir`) | confirmed | live CRAN policy |
| 55 | `curl::ie_get_proxy_for_url` exists; `aws_sigv4` in `curl_options()`; `multi_run(timeout, poll, pool)` | confirmed | local R |

Still unverifiable (left marked as such in the report): acceptance of the pure-R SigV4 signatures by real AWS; exact Bedrock
exception-type strings in a live ConverseStream capture; Ollama's reasoning field name on `/v1/chat/completions` (LIKELY
`reasoning`); Interactions SSE event names (only in the saved migration guide/reference copies, not on the live overview);
Gemini's on-the-wire SSE line terminators; all Windows-specific behaviour (not tested).

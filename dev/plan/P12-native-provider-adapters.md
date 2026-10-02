# P12 Native Provider Adapters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship gptr's four native wire adapters (`anthropic-messages`, `openai-responses`, `openai-completions`, `google-generative-ai`) with byte-exact replay of opaque provider data, request bodies driven by the cache plans of `prompt-cache.R`, `.opts$returns` support and a fixture-replay conformance check (REQ-11).

**Architecture:** Four L1 files. `R/provider-anthropic.R` holds the normaliser core every adapter shares (per-stream state, linear delta buffers, the INFRA-02 events with exactly one `start` and one terminal event, the retry hand-off), the Anthropic normaliser and request builder, and `check_adapter()` (the `check.adapter` service behind `gptr_check()`), which replays `tests/testthat/fixtures/sse/<api>/` whole, byte by byte and in deterministic pseudo-random chunkings against hand-written golden files; the three other files hold one adapter each (`compat_flags()` and the streaming `<think>` splitter live with Chat Completions). Each file registers its adapter from its own `builtin_<name>()` through `on_load(ext_declare_builtin())`; P05's `provider_stream()` drives the adapters on P04's reactor, and every request body is a concatenation of JSON pieces serialised once per session through `opts$memo`, so the frozen prefix stays byte-identical across turns.

**Tech Stack:** base R (>= 4.2.0); jsonlite, cli and rlang only through P01's `json_encode()`/`json_decode()`, `hash_sha256()` and `hash_xxh128()`; testthat 3e; withr and processx in tests only (processx through P01's mock server).

**Spec:** dev/spec/03-architecture.md (sections 3.2 rows `provider-*.R`, 3.4, 6.1, 6.3, 6.5, 6.6, 6.11, 6.18 rows INFRA-02/07/08/23/25, 8.1, 12.3), dev/spec/04-interface-contract.md (sections 2.2, 4.1-4.5, 4.9, 5.9, 5.11, 7.0 `check.adapter`, 7.1, 7.5, 7.12, 8.1-8.4, 10.2 rows 1-2, 10.3, 10.4 `request_params`, 12.2-12.4, 15: IC-33, IC-34, IC-35, IC-61, IC-62, IC-64, IC-67, IC-69, IC-71, IC-72), dev/spec/05-plan-decomposition.md (P12).

**Depends on:** P05, P07 (and P01-P04 through them; the INFRA-25 run test also uses P06's `session_run()`, which P07 already requires). **Milestone:** M2.

---

## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment and `|>` for pipes (never `<-` or `%>%`; `<<-` only for closure state), ASCII-only R sources (non-ASCII text written as backslash-u escapes), `pkg::fun()` calls, no `:::` in `R/`, no `.GlobalEnv`, `readLines(..., encoding = "UTF-8")`, testthat 3e, no network in tests, TDD, one commit per task whose message ends with the attribution line required by the executing harness (conventions section 10). Plan-specific requirements, copied from the specification:

- Owned files (05 P12): `R/provider-anthropic.R`, `R/provider-openai-responses.R`, `R/provider-openai-completions.R`, `R/provider-google.R`; `tests/testthat/test-provider-anthropic.R`, `tests/testthat/test-provider-openai-responses.R`, `tests/testthat/test-provider-openai-completions.R`, `tests/testthat/test-provider-google.R`; `tests/testthat/fixtures/sse/` (here: the generator `make_fixtures.R`, the shared test helpers `replay_helpers.R` and the generated `<api>/<case>.sse`, `.events.json`, `.message.json`, `model.json`); `tests/testthat/test-live-anthropic.R`, `tests/testthat/test-live-openai.R`, `tests/testthat/test-live-google.R`. P12 exports nothing (every function is `@noRd`), so `NAMESPACE` and `man/` do not change.
- Built-ins (04 section 10.3): `builtin:anthropic`, `builtin:openai`, `builtin:openai-compat`, `builtin:google` ("P12 files | adapters | yes"), each declared at the top level of its own file as `on_load(ext_declare_builtin("<name>", builtin_<name>))` with the factories `builtin_anthropic`, `builtin_openai`, `builtin_openai_compat`, `builtin_google` (04 section 7.12).
- Cross-plan functions (04 section 7.12), exact names and arguments: `anthropic_normaliser(model, opts)` -> "the Anthropic SSE normaliser (`push(ev)`, `finish()`, `fail(cnd)`, `message()`), accepting either SSE events or already-parsed stream-event objects (`push_parsed(obj)`)" (consumer P20); `check_adapter(adapter, fixtures = NULL)` (service `check.adapter`, signature `function(adapter, fixtures = NULL) <gptr_check>`, 04 section 7.0) -> "replays `fixtures/sse/<api>/*.sse` (or `fixtures`) through the adapter with random chunkings and compares with `<case>.events.json` / `<case>.message.json`; returns `gptr_check` rows" (consumers P02 `gptr_check()`, P24); `compat_flags(provider, model)` -> "the compat record of 09 section 3 (field names, `max_tokens` vs `max_completion_tokens`, `reasoning_content` replay, tool-id length, image modes)".
- Adapter specs (04 section 8.1, IC-35): `gptr_adapter(api, transport = c(...), build = NULL, parse = NULL, stream = NULL, classify = NULL, capabilities = list())`; all four adapters use `transport = "http_sse"`. `build(model, context, opts)` returns `list(url = chr(1), method = "POST", headers = named list of chr(1) or handles, body = chr(1) (UTF-8 JSON text assembled by concatenation of memoised pieces), stream = "sse")`; `parse(model, opts)` returns a normaliser `list(push, finish, fail, message)`.
- Request context (04 section 8.1, built by P07's `request_build()`): `system = list(t0, t1)`, `tools_json` (json_verbatim, Anthropic shape of 04 section 9.2, "adapters convert it once per session and keep the conversion in `opts$memo`"), `tools`, `messages`, `cache_plan = list(anchors = chr element ids ("t0", "project"), tail_ttl = "5m" | "1h", key = chr(1))`, `params = list(max_tokens, thinking, effort, tool_choice = "auto" | "none" | list, returns = JSON Schema | NULL, temperature)`, `session_id`, `request_id`.
- Options read by the adapters (04 section 8.1): `emit(ev)`, `retry(info)` with `info = list(class, status, retry_after)` ("The transport retries only if no delta was committed; otherwise it calls `fail()`"), `signal` (environment with `aborted`, `reason`), `credential` (a `gptr_secret` handle "adapters put it in `headers` as a handle, never as a value"), `base_url`, `memo` (environment). Adapters never call L2+ functions (IC-33).
- Normalisers (04 section 8.1): `push(ev)` takes `list(event, data, id)` and returns `TRUE` once the terminal event was emitted; `finish()` emits the terminal event if not yet emitted ("`done`, or `error` for a truncated stream") and returns the final message; `fail(cnd)` "emits `error` with the partial message and returns it"; `message()` is "materialised lazily; never per delta". "Normalisers never signal R conditions after `start`; every failure becomes exactly one terminal `error` event carrying the partial message (INFRA-02). Opaque provider data (signatures, encrypted reasoning, `phase`, thought signatures) is stored byte for byte (INFRA-07). Deltas accumulate in preallocated lists joined once."
- Events (04 section 4.5): `start` (`api`, `provider`, `model`, `request_id`, `response_id`) exactly once and first; `text_start`/`text_delta`/`text_end`, `thinking_start`/`thinking_delta`/`thinking_end` (`index`; `delta`; `block`); `toolcall_start` (`index`, `id`, `name`), `toolcall_delta` (`delta`, `preview` throttled to 10 Hz by `json-partial.R`), `toolcall_end` (`block`); `done` (`reason`, `message`, `usage`); `error` (`reason` `"error"` or `"aborted"`, `message`, `error = list(class, status, request_id, retry_after)`). `index` is 1-based. Every event is built with `ev_new()`.
- Capabilities (04 section 8.1, IC-69, IC-71): `images_in_results`, `tool_addition`, `structured_output`, `reasoning_replay`, `parallel_tools`, `forced_tool_choice` ("`FALSE` for Anthropic 5.x models"), `request_params` ("non-prefix request fields a `request_params` handler may patch"), `operator_role` (`"system"`, `"developer"`, `"user"`), `cache` (`"anthropic"`, `"openai"`, `"gemini"`, `"openrouter"`, `"none"`), `max_tool_name`, `tool_shape` (`"anthropic"`, `"responses"`, `"chat"`, `"gemini"`). Values used here:

  | Adapter | images_in_results | tool_addition | structured_output | forced_tool_choice | request_params | operator_role | cache | max_tool_name | tool_shape |
  |---|---|---|---|---|---|---|---|---|---|
  | `anthropic-messages` | TRUE | TRUE | TRUE | FALSE | `service_tier`, `metadata` | system | anthropic | 128 | anthropic |
  | `openai-responses` | TRUE | TRUE | FALSE | TRUE | `service_tier`, `metadata`, `safety_identifier` | developer | openai | 64 | responses |
  | `openai-completions` | FALSE | FALSE | FALSE | TRUE | `service_tier`, `metadata`, `user` | user | openrouter | 64 | chat |
  | `google-generative-ai` | TRUE | FALSE | FALSE | TRUE | `labels`, `service_tier` | user | gemini | 128 | gemini |

  All four set `reasoning_replay = TRUE` and `parallel_tools = TRUE`. A model's own `capabilities$forced_tool_choice` (P05 catalog, IC-71) wins over the adapter's.
- Forced tool choice and `returns` (IC-71): "model capability `forced_tool_choice` (`FALSE` for Anthropic 5.x); `returns =` uses `output_config.format` on Anthropic, elsewhere `auto` + instruction + validation; `gptr_check()` rejects adapters sending a list `tool_choice` when the capability is `FALSE`". Validation of the final answer is P06's `run_returns()`.
- `request_params` (IC-69): "payload `params` limited to the fields the adapter declares non-prefix (`capabilities$request_params`, e.g. `service_tier`, `metadata`, `user`)"; an adapter copies exactly those fields of `context$params` into the body.
- Caching (architecture section 6.11, G4 sections 3.7-3.8): Anthropic "BP1 end of T0 system block (1h), BP2 project block or T1 block (1h), automatic tail (5m default; 1h adaptive)" with body key order "model, max_tokens, stream, cache_control, thinking, tools, system, messages"; OpenAI Responses "model, store=false, stream, prompt_cache_key, prompt_cache_options, reasoning, tools, input", a developer message with "two `input_text` blocks, each `prompt_cache_breakpoint: {mode: explicit}`", the project block with an explicit breakpoint, `prompt_cache_options: {mode: "implicit"}`, `prompt_cache_key` = "`gptr:` + 12 hex of the project root hash (<= 64 chars)"; Gemini "systemInstruction, tools, generationConfig, contents" with implicit caching only; OpenAI-compatible "model, stream, stream_options, tools, messages", "OpenRouter: `session_id`; `cache_control` on the project block and system for anthropic/* and google/* models". Breakpoints follow `context$cache_plan$anchors`; the tail TTL follows `context$cache_plan$tail_ttl`.
- Endpoints and credentials (architecture section 8.1; reports 07 section 2.2, 08 section 3.1, 09 section 3.1 and verification row 2): Anthropic `POST {base}/v1/messages` with `x-api-key` (or `Authorization: Bearer` plus `anthropic-beta: oauth-2025-04-20` for an `ANTHROPIC_AUTH_TOKEN` handle; "never sends both") and `anthropic-version: 2023-06-01`; OpenAI `POST {base}/responses` with `Authorization: Bearer` and a unique `x-client-request-id` per request; Chat Completions `POST {base}/chat/completions` with `Authorization: Bearer` (Azure: `api-key`); Gemini `POST {base}/models/{id}:streamGenerateContent?alt=sse` with the key in `x-goog-api-key` (never in the URL). Headers hold handles (or `list(prefix, handle)`); only P04's `http-request.R` materialises them.
- Anthropic betas (reports 07 section 3.8, G4 sections 2.3 and 3.7): `interleaved-thinking-2025-05-14` for budget-thinking models, `inline-tools-2026-09-15` when an operator message carries `tool_addition` blocks, `oauth-2025-04-20` for Bearer tokens.
- Stop reasons (04 section 4.2): `stop`, `length`, `tool_use`, `aborted`, `error`, `refusal`, `pause`; unknown provider values map to `error` with `raw_stop_reason` kept (architecture section 8.1: "unknown finish reasons map to error with the raw value").
- Error classes in `error` events are 04 section 2.2 suffixes: `overloaded`, `rate_limit`, `spend_cap` (Anthropic `enforced_spend_limit_reached`, "never retried"), `auth`, `network` (truncated stream), `provider`, `internal`.
- Compat field names (P05 Task 2, the contract `compat_flags()` reads): `supports_store`, `supports_developer_role`, `supports_reasoning_effort`, `supports_strict_mode`, `supports_tool_choice`, `max_tokens_field`, `requires_tool_result_name`, `requires_reasoning_content`, `thinking_format`, `thinking_in_content`, `think_tags`, `cache_control_format`, `session_affinity`, `image_mode`, `tool_id` (`"alnum9"`), `auth_header`, `deployment_model`; P12 adds the defaults `supports_usage_in_streaming`, `supports_finish_reason`, `requires_assistant_after_tool_result`, `requires_thinking_as_text`, `explicit_cache_mode` (report 09 section 3.3 flags), and accepts Pi's camelCase names in provider records.
- Randomness and encoding (IC-61, IC-62): chunkings for conformance replay come from sha256 hash bits, never from R's RNG; every string an adapter creates goes through P01's constructors, which mark UTF-8.
- Tests: offline, fixture replay through the real normalisers, P04's `reactor_http()` replaced with `testthat::local_mocked_bindings()` for scripted wires, P01's `local_mock_server()` (skips on CRAN) for end-to-end streams; live tests begin with `skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"))` plus a key check (conventions section 7). Golden files are written by hand in `make_fixtures.R`, never computed by gptr. 04 section 12.3: "fixtures store events without the volatile fields `ts`, `session`, `run`, `request_id`; comparisons use `expect_equal()` on the JSON-decoded lists".
- Test filters: testthat matches `filter` against the file name without `test-` and `.R`, so `filter = "live"` also selects P06's `test-session-live.R` (and, later, P13's `test-live-jev.R`). This plan selects its own live files with `filter = "^live-(anthropic|openai|google)$"`; the other filters (`provider-anthropic`, `provider-openai-completions`, `provider-openai-responses`, `provider-google`, `provider-(anthropic|openai|google)`) match only P12's test files.
- Mid-conversation `system` messages (report 07 section 2.3 and verification row 14): only on models with `mid_system`; each "must follow a user message ... AND must be either the last entry in `messages` or be followed by an `assistant` turn", so a run of operator messages is sent as one system message, never as consecutive system messages.
- Sampling parameters (report 07 section 2.3): "`temperature`/`top_p`/`top_k`: non-default values are 400 on all 5.x models", so the Anthropic adapter sends `temperature` only to models without adaptive thinking and only when no thinking is configured.
- Precondition from P02 (see Task 3 and the self-review): 04 section 7.12 gives the name `check_adapter()` to P12, so P02's `R/ext-check.R` must not define a function of that name (its private per-spec helper is renamed, for example to `check_adapter_rows()`); two definitions of one name in `R/` let the later-collating file replace the other silently.

## File Structure

| File | Responsibility |
|---|---|
| `R/provider-anthropic.R` | the normaliser core shared by all adapters (`adp_*`: state, linear buffers, events, terminal handling, retry hand-off, usage, request-body helpers, golden projection and replay); the `anthropic-messages` normaliser (`anthropic_normaliser()`) and request builder (`anthropic_build()`); `builtin_anthropic()`; `check_adapter()` and the `check.adapter` service |
| `R/provider-openai-completions.R` | `compat_flags()` and the compat defaults, the streaming `think_splitter()`, tool-id rules, the `openai-completions` normaliser and request builder, `builtin_openai_compat()` |
| `R/provider-openai-responses.R` | the `openai-responses` normaliser (reasoning items, `phase`, `call_|fc_` ids, encrypted-content backfill) and request builder (stateless `store = false`, explicit breakpoints, `additional_tools`), `builtin_openai()` |
| `R/provider-google.R` | the `google-generative-ai` normaliser (thought signatures on the exact part, finish reasons, generated call ids) and request builder (thinking levels and budgets, `functionResponse` images), `builtin_google()` |
| `tests/testthat/test-provider-anthropic.R` | core, Anthropic normaliser and body, breakpoints, returns, `check_adapter()`, scripted run (INFRA-25), mock-server end to end |
| `tests/testthat/test-provider-openai-completions.R` | compat flags, `<think>` splitter, tool ids, normaliser, bodies, mock-server stream |
| `tests/testthat/test-provider-openai-responses.R` | normaliser, replay of reasoning items, bodies, the INFRA-08 hand-off body (Anthropic -> Responses), scripted run, mock-server stream |
| `tests/testthat/test-provider-google.R` | normaliser, thought-signature replay, bodies, the INFRA-08 hand-off body (Anthropic -> Responses -> Gemini), mock-server stream |
| `tests/testthat/test-live-anthropic.R`, `test-live-openai.R`, `test-live-google.R` | gated live round trips (`GPTR_LIVE_TESTS=true` and a key) |
| `tests/testthat/fixtures/sse/make_fixtures.R` | writes every `<api>/<case>.sse` with its hand-written golden `.events.json` and `.message.json` (and `model.json` overrides); run from the repository root |
| `tests/testthat/fixtures/sse/replay_helpers.R` | test helpers sourced by every P12 test file (fixture replay, golden comparison, request contexts, scripted wire, mock-server driver, the INFRA-08 hand-off transcript and the closed Responses and Gemini body schemas, live helpers) |
| `tests/testthat/fixtures/sse/<api>/...` | generated wire fixtures: `anthropic-messages` (6 cases), `openai-completions` (4), `openai-responses` (5), `google-generative-ai` (5) |

Every command runs from the repository root (`/Users/wanjun/Desktop/gptr`) with `Rscript --vanilla`. `devtools::test()` sets `NOT_CRAN=true`, so the mock-server tests run; under `R CMD check --as-cran` they skip.

## Tasks

1. Shared normaliser core and the Anthropic normaliser (`provider-anthropic.R`)
2. Anthropic request bodies and `builtin:anthropic` (`provider-anthropic.R`)
3. `check_adapter()` and the `check.adapter` service (`provider-anthropic.R`)
4. Chat Completions compat flags, `<think>` splitter and normaliser (`provider-openai-completions.R`)
5. Chat Completions request bodies and `builtin:openai-compat` (`provider-openai-completions.R`)
6. Responses normaliser (`provider-openai-responses.R`)
7. Responses request bodies and `builtin:openai` (`provider-openai-responses.R`)
8. Gemini normaliser (`provider-google.R`)
9. Gemini request bodies and `builtin:google` (`provider-google.R`)
10. Gated live tests (`test-live-*.R`)

---

### Task 1: Shared normaliser core and the Anthropic normaliser

**Files:**
- Create: `R/provider-anthropic.R`
- Create: `tests/testthat/fixtures/sse/make_fixtures.R` (generator) and, by running it, `tests/testthat/fixtures/sse/anthropic-messages/` (18 files)
- Create: `tests/testthat/fixtures/sse/replay_helpers.R`
- Test: `tests/testthat/test-provider-anthropic.R` (create)

**Interfaces:**
- Consumes (04 sections 4.1-4.5, 7.1, 7.4, 7.5, 8.3): `ev_new(type, ...)`; `block_text(text, signature = NULL)`, `block_thinking(thinking, signature = NULL, redacted = FALSE, data = NULL, origin = NULL)`, `block_tool_call(id, name, arguments, raw_arguments = NULL, thought_signature = NULL)`, `block_opaque(provider, api, model, json)`, `msg_assistant(content, api, provider, model, usage = NULL, stop_reason = "stop", response_id = NULL, response_model = NULL, error_message = NULL, raw_stop_reason = NULL, thinking_level = NULL, route = "api", request_id = NULL, timestamp = NULL)`; `json_encode(x)`, `json_decode(text)`, `json_obj()`; `partial_json()` (an environment with `push(delta)` and `preview()`); `hash_sha256(x)`; `read_utf8(path)` (-> `list(text, ...)`); `raw_to_utf8(x, fallback = "CP1252")`; `%||%` (P01). `usage_new(...)`, `usage_cost(usage, model, when = Sys.Date())` (P05). `sse_splitter()` (`push(raw)` -> list of `list(event, data, id, retry)`, `flush()` -> one event or `NULL`), `ndjson_splitter()` (P04).
- Produces: `anthropic_normaliser(model, opts)` -> `list(push(ev), push_parsed(obj), finish(), fail(cnd), message())` (04 section 7.12). The private core every later task uses: `adp_state(model, opts)`, `adp_open(st, type, ...)` (types `text`, `thinking`, `tool_call`, `opaque`; returns the 1-based index), `adp_delta(st, i, text)`, `adp_close(st, i)`, `adp_set_opaque(st, i, json)`, `adp_message(st)`, `adp_error(st, message, class = "provider", status = NA_integer_, retry_after = NULL, aborted = FALSE)`, `adp_done(st)`, `adp_stream_error(st, opts, message, class, status = NA_integer_, retry_after = NULL, retryable = FALSE)`, `adp_finish_pending(st)`, `adp_fail(st, cnd)`, `adp_normaliser(st, push, finish, push_parsed = NULL)` (which wraps each step in `adp_guard(st, f)`), `adp_route(model)`, `adp_json_try(text)`, `adp_is_object(x)`, `adp_chr(x)`, `adp_buffer_text(b)`; and for tests and Task 3: `adp_golden_event(ev)`, `adp_golden_message(m)`, `adp_chunk_sizes(key)`, `adp_replay(adapter, model, bytes, sizes)`, `adp_fixture_model(api, dir = NULL)`.

The core follows the verified accumulator of report 07 section 5.1 and report 03 section 5.3, rewritten as a state machine of environments so that a delta costs O(1): each content slot keeps its deltas in a list that doubles when full and is joined once (the list is taken out of its environment and the binding cleared before an element is set; assigning `b$v[[n]] = x` on an environment passed as an argument copies the whole list on every call, which was measured at 1.7 s for 20,000 appends). `start` is emitted lazily before the first content event or the terminal event; a retryable in-stream failure before any delta calls `opts$retry(info)` and leaves the stream open for the transport to restart (04 section 8.1); every R error inside a normaliser step becomes the one terminal `error` event (class `internal`). Anthropic specifics (report 07 sections 2.4, 2.10, 2.11, 5.1 and its verification log): `$` partial matching is avoided for usage fields (`cache_creation` vs `cache_creation_input_tokens`), the 5-minute and 1-hour cache writes are split, `refusal` keeps `stop_details.explanation`, `pause_turn` maps to `pause`, server-tool and unknown blocks are kept as opaque JSON with their streamed `input`, and the spend-cap 429 (`enforced_spend_limit_reached`) is never retried.

The fixtures are raw SSE bytes with golden files written by hand (04 section 12.4): `text` (CRLF line ends, a comment line, a `ping`, multi-byte UTF-8 text), `thinking_tools` (signed thinking, redacted thinking, parallel tool use, 5-minute and 1-hour cache writes), `error_midstream` (an overload `error` event after a delta), `truncated` (the connection ends inside a tool call), `refusal`, `server_tool` (server-tool blocks kept as opaque JSON).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/sse/make_fixtures.R`:

```r
# Writes the P12 wire fixtures: tests/testthat/fixtures/sse/<api>/<case>.sse (raw stream bytes)
# with the hand-specified golden files <case>.events.json and <case>.message.json (contract
# sec 12.4). The golden values are written here by hand, never computed by gptr.
# Run from the repository root: Rscript --vanilla tests/testthat/fixtures/sse/make_fixtures.R
# ASCII only: non-ASCII text is written with \u escapes, which are marked UTF-8 in every locale.

root = file.path("tests", "testthat", "fixtures", "sse")
if (!dir.exists(root)) stop("run from the repository root")

to_json = function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE))
}
write_text = function(path, text) {
  con = file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(text), con)
}
obj = function() structure(list(), names = character())
drop_null = function(x) x[!vapply(x, is.null, logical(1))]
js = function(...) paste0(...)

# ---- stream builders -----------------------------------------------------------------------
ev = function(event, data) paste0("event: ", event, "\n", "data: ", data, "\n\n")
dat = function(data) paste0("data: ", data, "\n\n")

# ---- golden builders (key order = the order of adp_golden_*() in provider-anthropic.R) ------
g_text = function(text, signature = NULL) {
  drop_null(list(type = "text", text = text, signature = signature))
}
g_think = function(thinking, signature = NULL, redacted = NULL, data = NULL) {
  drop_null(list(type = "thinking", thinking = thinking, signature = signature,
                 redacted = redacted, data = data))
}
g_tool = function(id, name, arguments, raw = NULL, sig = NULL) {
  drop_null(list(type = "tool_call", id = id, name = name, arguments = arguments,
                 raw_arguments = raw, thought_signature = sig))
}
g_opaque = function(json) list(type = "opaque", json = json)
e_start = function(rid) list(type = "start", response_id = rid)
e_open = function(kind, i) list(type = paste0(kind, "_start"), index = i)
e_delta = function(kind, i, d) list(type = paste0(kind, "_delta"), index = i, delta = d)
e_end = function(kind, i, block) list(type = paste0(kind, "_end"), index = i, block = block)
e_tstart = function(i, id, name) list(type = "toolcall_start", index = i, id = id, name = name)
e_done = function(reason) list(type = "done", reason = reason)
e_error = function(class, status = NULL) {
  list(type = "error", reason = "error", error = list(class = class, status = status))
}
g_usage = function(input = 0, output = 0, cache_read = 0, w5 = 0, w1 = 0, reasoning = 0) {
  list(input = input, output = output, cache_read = cache_read, cache_write_5m = w5,
       cache_write_1h = w1, reasoning = reasoning,
       total = input + output + cache_read + w5 + w1)
}
g_msg = function(stop, raw = NULL, err = NULL, rid = NULL, rmodel = NULL, content = list(),
                 usage = g_usage()) {
  drop_null(list(stop_reason = stop, raw_stop_reason = raw, error_message = err,
                 response_id = rid, response_model = rmodel, content = content,
                 usage = usage))
}
write_case = function(api, case, stream, events, message, eol = "\n") {
  dir = file.path(root, api)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  stream = paste(stream, collapse = "")
  if (!identical(eol, "\n")) stream = gsub("\n", eol, stream, fixed = TRUE)
  write_text(file.path(dir, paste0(case, ".sse")), stream)
  write_text(file.path(dir, paste0(case, ".events.json")), paste0(to_json(events), "\n"))
  write_text(file.path(dir, paste0(case, ".message.json")), paste0(to_json(message), "\n"))
}
# ============================================================================================
# anthropic-messages
# ============================================================================================
a = "anthropic-messages"
greet = "caf\u00e9 \u2014 \U0001F600."

a_text = c(
  ": keep-alive\n\n",
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01TEXT",',
    '"type":"message","role":"assistant","model":"claude-sonnet-5-5",',
    '"content":[],"stop_reason":null,"stop_sequence":null,',
    '"usage":{"input_tokens":12,"cache_read_input_tokens":0,',
    '"cache_creation_input_tokens":0,"output_tokens":1}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"text","text":""}}'
  )),
  ev("ping", '{"type":"ping"}'),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"text_delta","text":"Hello, "}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"text_delta","text":"',
    greet,
    '"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":0}'),
  ev("message_delta", js(
    '{"type":"message_delta","delta":{"stop_reason":"end_turn",',
    '"stop_sequence":null},"usage":{"output_tokens":9}}'
  )),
  ev("message_stop", '{"type":"message_stop"}')
)
write_case(
  a, "text", a_text,
  list(e_start("msg_01TEXT"), e_open("text", 1L), e_delta("text", 1L, "Hello, "),
       e_delta("text", 1L, greet), e_end("text", 1L, g_text(paste0("Hello, ", greet))),
       e_done("stop")),
  g_msg("stop", "end_turn", rid = "msg_01TEXT", rmodel = "claude-sonnet-5-5",
        content = list(g_text(paste0("Hello, ", greet))), usage = g_usage(12, 9)),
  eol = "\r\n"
)

sig = "EqQBCgIYAhIM1gbcDa9GJwZA2b3hGgxBdjrkzLoky3dl1pkiMOYds=="
red = "EmwKAhgBEgy3va3pzix/LafPsn4aDFIT2Xlxh0L5L8rLVyIwxtE3rAFBa8cr3qpP"
think = "The user wants mpg by cyl. Aggregate in the session."

a_tools = c(
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01TOOLS",',
    '"type":"message","role":"assistant","model":"claude-opus-5-5",',
    '"content":[],"stop_reason":null,"stop_sequence":null,',
    '"usage":{"input_tokens":2140,"cache_read_input_tokens":18000,',
    '"cache_creation_input_tokens":1200,',
    '"cache_creation":{"ephemeral_5m_input_tokens":200,',
    '"ephemeral_1h_input_tokens":1000},"output_tokens":3}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"thinking","thinking":"","signature":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"thinking_delta",',
    '"thinking":"The user wants mpg by cyl. "}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"thinking_delta",',
    '"thinking":"Aggregate in the session."}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"signature_delta","signature":"',
    sig,
    '"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":0}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":1,',
    '"content_block":{"type":"redacted_thinking","data":"',
    red,
    '"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":1}'),
  ev("future_event", '{"type":"future_event","detail":1}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":2,',
    '"content_block":{"type":"text","text":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":2,',
    '"delta":{"type":"text_delta","text":"I will compute that."}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":2}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":3,',
    '"content_block":{"type":"tool_use","id":"toolu_01A","name":"r",',
    '"input":{}}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":3,',
    '"delta":{"type":"input_json_delta","partial_json":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":3,',
    '"delta":{"type":"input_json_delta",',
    '"partial_json":"{\\"code\\": \\"aggregate(mpg ~ cyl"}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":3,',
    '"delta":{"type":"input_json_delta","partial_json":", mtcars,',
    ' mean)\\"}"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":3}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":4,',
    '"content_block":{"type":"tool_use","id":"toolu_01B","name":"read",',
    '"input":{}}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":4,',
    '"delta":{"type":"input_json_delta",',
    '"partial_json":"{\\"path\\":\\"R/a.R\\"}"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":4}'),
  ev("message_delta", js(
    '{"type":"message_delta","delta":{"stop_reason":"tool_use",',
    '"stop_sequence":null},"usage":{"output_tokens":187,',
    '"output_tokens_details":{"thinking_tokens":61}}}'
  )),
  ev("message_stop", '{"type":"message_stop"}')
)
code_args = list(code = "aggregate(mpg ~ cyl, mtcars, mean)")
write_case(
  a, "thinking_tools", a_tools,
  list(e_start("msg_01TOOLS"), e_open("thinking", 1L),
       e_delta("thinking", 1L, "The user wants mpg by cyl. "),
       e_delta("thinking", 1L, "Aggregate in the session."),
       e_end("thinking", 1L, g_think(think, signature = sig)),
       e_open("thinking", 2L), e_end("thinking", 2L, g_think("", redacted = TRUE, data = red)),
       e_open("text", 3L), e_delta("text", 3L, "I will compute that."),
       e_end("text", 3L, g_text("I will compute that.")),
       e_tstart(4L, "toolu_01A", "r"),
       e_delta("toolcall", 4L, "{\"code\": \"aggregate(mpg ~ cyl"),
       e_delta("toolcall", 4L, ", mtcars, mean)\"}"),
       e_end("toolcall", 4L, g_tool("toolu_01A", "r", code_args)),
       e_tstart(5L, "toolu_01B", "read"),
       e_delta("toolcall", 5L, "{\"path\":\"R/a.R\"}"),
       e_end("toolcall", 5L, g_tool("toolu_01B", "read", list(path = "R/a.R"))),
       e_done("tool_use")),
  g_msg("tool_use", "tool_use", rid = "msg_01TOOLS", rmodel = "claude-opus-5-5",
        content = list(g_think(think, signature = sig),
                       g_think("", redacted = TRUE, data = red),
                       g_text("I will compute that."),
                       g_tool("toolu_01A", "r", code_args),
                       g_tool("toolu_01B", "read", list(path = "R/a.R"))),
        usage = g_usage(2140, 187, 18000, 200, 1000, 61))
)

a_error = c(
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01ERR",',
    '"type":"message","role":"assistant","model":"claude-sonnet-5-5",',
    '"content":[],"stop_reason":null,"usage":{"input_tokens":25,',
    '"output_tokens":1}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"text","text":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"text_delta","text":"Partial ans"}}'
  )),
  ev("error", js(
    '{"type":"error","error":{"type":"overloaded_error",',
    '"message":"Overloaded"}}'
  ))
)
write_case(
  a, "error_midstream", a_error,
  list(e_start("msg_01ERR"), e_open("text", 1L), e_delta("text", 1L, "Partial ans"),
       e_error("overloaded", 529L)),
  g_msg("error", err = "overloaded_error: Overloaded", rid = "msg_01ERR",
        rmodel = "claude-sonnet-5-5", content = list(g_text("Partial ans")),
        usage = g_usage(25, 1))
)

a_cut = c(
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01CUT",',
    '"type":"message","role":"assistant","model":"claude-sonnet-5-5",',
    '"content":[],"stop_reason":null,"usage":{"input_tokens":25,',
    '"output_tokens":1}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"tool_use","id":"toolu_01C","name":"write",',
    '"input":{}}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"input_json_delta",',
    '"partial_json":"{\\"path\\": \\"a.R\\", \\"content\\": \\"x = "}}'
  ))
)
cut_raw = "{\"path\": \"a.R\", \"content\": \"x = "
write_case(
  a, "truncated", a_cut,
  list(e_start("msg_01CUT"), e_tstart(1L, "toolu_01C", "write"),
       e_delta("toolcall", 1L, cut_raw), e_error("network")),
  g_msg("error", err = "The Anthropic stream ended before message_stop.", rid = "msg_01CUT",
        rmodel = "claude-sonnet-5-5",
        content = list(g_tool("toolu_01C", "write", obj(), raw = cut_raw)),
        usage = g_usage(25, 1))
)

a_refusal = c(
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01REF",',
    '"type":"message","role":"assistant","model":"claude-sonnet-5-5",',
    '"content":[],"stop_reason":null,"usage":{"input_tokens":30,',
    '"output_tokens":1}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"text","text":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"text_delta","text":"I cannot help with that."}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":0}'),
  ev("message_delta", js(
    '{"type":"message_delta","delta":{"stop_reason":"refusal",',
    '"stop_sequence":null,"stop_details":{"type":"refusal",',
    '"category":"cyber","explanation":"The request was declined."}},',
    '"usage":{"output_tokens":7}}'
  )),
  ev("message_stop", '{"type":"message_stop"}')
)
write_case(
  a, "refusal", a_refusal,
  list(e_start("msg_01REF"), e_open("text", 1L), e_delta("text", 1L, "I cannot help with that."),
       e_end("text", 1L, g_text("I cannot help with that.")), e_done("refusal")),
  g_msg("refusal", "refusal", err = "The request was declined.", rid = "msg_01REF",
        rmodel = "claude-sonnet-5-5", content = list(g_text("I cannot help with that.")),
        usage = g_usage(30, 7))
)

stu = js(
  '{"type":"server_tool_use","id":"srvtoolu_01","name":"web_search",',
  '"input":{"query":"R 4.4 news"}}'
)

wsr = js(
  '{"type":"web_search_tool_result","tool_use_id":"srvtoolu_01",',
  '"content":[{"type":"web_search_result",',
  '"url":"https://example.org/r","title":"R news",',
  '"encrypted_content":"EqgfCioIARgB"}]}'
)

a_server = c(
  ev("message_start", js(
    '{"type":"message_start","message":{"id":"msg_01SRV",',
    '"type":"message","role":"assistant","model":"claude-sonnet-5-5",',
    '"content":[],"stop_reason":null,"usage":{"input_tokens":40,',
    '"output_tokens":1}}}'
  )),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":0,',
    '"content_block":{"type":"server_tool_use","id":"srvtoolu_01",',
    '"name":"web_search","input":{}}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":0,',
    '"delta":{"type":"input_json_delta",',
    '"partial_json":"{\\"query\\":\\"R 4.4 news\\"}"}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":0}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":1,"content_block":',
    wsr,
    "}"
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":1}'),
  ev("content_block_start", js(
    '{"type":"content_block_start","index":2,',
    '"content_block":{"type":"text","text":""}}'
  )),
  ev("content_block_delta", js(
    '{"type":"content_block_delta","index":2,',
    '"delta":{"type":"text_delta","text":"R 4.4 is out."}}'
  )),
  ev("content_block_stop", '{"type":"content_block_stop","index":2}'),
  ev("message_delta", js(
    '{"type":"message_delta","delta":{"stop_reason":"end_turn",',
    '"stop_sequence":null},"usage":{"output_tokens":20}}'
  )),
  ev("message_stop", '{"type":"message_stop"}')
)
write_case(
  a, "server_tool", a_server,
  list(e_start("msg_01SRV"), e_open("text", 3L), e_delta("text", 3L, "R 4.4 is out."),
       e_end("text", 3L, g_text("R 4.4 is out.")), e_done("stop")),
  g_msg("stop", "end_turn", rid = "msg_01SRV", rmodel = "claude-sonnet-5-5",
        content = list(g_opaque(stu), g_opaque(wsr), g_text("R 4.4 is out.")),
        usage = g_usage(40, 20))
)
```

Run it from the repository root to write the Anthropic fixtures:

```bash
Rscript --vanilla tests/testthat/fixtures/sse/make_fixtures.R
ls tests/testthat/fixtures/sse/anthropic-messages | wc -l
```

Expected: the script prints nothing and the count is `18` (`error_midstream`, `refusal`, `server_tool`, `text`, `thinking_tools`, `truncated`, each with `.sse`, `.events.json` and `.message.json`).

Create `tests/testthat/fixtures/sse/replay_helpers.R` (P12 owns `fixtures/sse/` and no `helper-*.R` file, so every P12 test file sources this file):

```r
# Shared helpers of the P12 adapter tests. P12 owns tests/testthat/fixtures/sse/ and no
# helper-*.R file, so every test-provider-*.R and test-live-*.R file sources this file first
# (local = TRUE, through testthat::test_path()).

# The fixture directory of an api
sse_dir = function(api) testthat::test_path("fixtures", "sse", api)

# An event collector: log$emit(ev) appends to log$events
event_log = function() {
  log = new.env(parent = emptyenv())
  log$events = list()
  log$emit = function(ev) log$events[[length(log$events) + 1L]] = ev
  log
}

# The types of a list of events
types_of = function(events) vapply(events, function(e) e$type %||% "", "")

# Replay one fixture through a normaliser in the given chunk sizes (whole stream by default)
replay_case = function(api, parse, case, sizes = NULL) {
  dir = sse_dir(api)
  path = file.path(dir, paste0(case, ".sse"))
  bytes = readBin(path, "raw", file.size(path))
  adapter = list(api = api, transport = "http_sse", parse = parse)
  adp_replay(adapter, adp_fixture_model(api, dir), bytes, sizes %||% length(bytes))
}

# Compare x with a golden JSON file of the fixture directory (04 section 12.4)
expect_golden = function(x, api, file) {
  want = json_decode(read_utf8(file.path(sse_dir(api), file))$text)
  testthat::expect_equal(json_decode(json_encode(x)), want)
}

# The golden check of every case of an api: events and the final message
expect_all_golden = function(api, parse) {
  cases = sub("\\.sse$", "", list.files(sse_dir(api), pattern = "\\.sse$"))
  testthat::expect_gt(length(cases), 0L)
  for (case in cases) {
    r = replay_case(api, parse, case)
    testthat::expect_null(r$condition)
    expect_golden(lapply(r$events, adp_golden_event), api, paste0(case, ".events.json"))
    expect_golden(adp_golden_message(r$message), api, paste0(case, ".message.json"))
  }
}

# Byte-by-byte and three pseudo-random chunkings give the events of the whole stream (INFRA-23)
expect_chunk_invariant = function(api, parse, case) {
  whole = lapply(replay_case(api, parse, case)$events, adp_golden_event)
  for (sz in list(1L, adp_chunk_sizes("a"), adp_chunk_sizes("b"), adp_chunk_sizes("c"))) {
    got = lapply(replay_case(api, parse, case, sz)$events, adp_golden_event)
    testthat::expect_identical(got, whole)
  }
}

# Exactly one start event first and exactly one terminal event last
expect_one_terminal = function(events) {
  types = types_of(events)
  testthat::expect_identical(types[[1L]], "start")
  testthat::expect_identical(sum(types == "start"), 1L)
  testthat::expect_identical(sum(types %in% c("done", "error")), 1L)
  testthat::expect_true(types[[length(types)]] %in% c("done", "error"))
}

# A model record (04 section 4.9) for normaliser and request-builder tests
test_model = function(api, id = "fixture-1", provider = "fixture", ...) {
  m = adp_fixture_model(api)
  m$id = id
  m$provider = provider
  m$ref = paste0(provider, "/", id)
  over = list(...)
  for (k in names(over)) m[[k]] = over[[k]]
  m
}
```

Create `tests/testthat/test-provider-anthropic.R`:

```r
# Tests for R/provider-anthropic.R (plan P12): the shared normaliser core, the
# anthropic-messages normaliser and request body, and check_adapter().
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

api = "anthropic-messages"

# ---- the normaliser (Task 1) -----------------------------------------------------------------

test_that("anthropic fixtures give the golden events and final messages (INFRA-02)", {
  expect_all_golden(api, anthropic_normaliser)
})

test_that("every anthropic fixture has one start first and one terminal event last", {
  for (case in c("text", "thinking_tools", "error_midstream", "truncated", "refusal",
                 "server_tool")) {
    expect_one_terminal(replay_case(api, anthropic_normaliser, case)$events)
  }
})

test_that("anthropic events do not depend on how the bytes are chunked (INFRA-23)", {
  for (case in c("text", "thinking_tools", "truncated")) {
    expect_chunk_invariant(api, anthropic_normaliser, case)
  }
})

test_that("text is UTF-8 and usage splits 5-minute and 1-hour cache writes", {
  r = replay_case(api, anthropic_normaliser, "text")
  expect_identical(Encoding(r$message$content[[1L]]$text), "UTF-8")
  expect_match(r$message$content[[1L]]$text, "caf\u00e9 \u2014 \U0001F600", fixed = TRUE)
  u = replay_case(api, anthropic_normaliser, "thinking_tools")$message$usage
  expect_identical(c(u$cache_write_5m, u$cache_write_1h, u$reasoning), c(200, 1000, 61))
})

test_that("a server error event and a truncated stream each end with one error and the partial", {
  err = replay_case(api, anthropic_normaliser, "error_midstream")
  last = err$events[[length(err$events)]]
  expect_identical(last$type, "error")
  expect_identical(last$error$class, "overloaded")
  expect_identical(last$message$stop_reason, "error")
  expect_identical(last$message$content[[1L]]$text, "Partial ans")
  cut = replay_case(api, anthropic_normaliser, "truncated")
  last = cut$events[[length(cut$events)]]
  expect_identical(last$type, "error")
  expect_identical(last$error$class, "network")
  expect_identical(last$message$content[[1L]]$raw_arguments,
                   "{\"path\": \"a.R\", \"content\": \"x = ")
})

test_that("an overload before any delta asks the transport to retry instead of failing", {
  log = event_log()
  retried = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit, retry = retried$emit))
  n$push(list(event = "message_start", data = paste0(
    '{"type":"message_start","message":{"id":"msg_r","model":"fixture-1",',
    '"usage":{"input_tokens":5,"output_tokens":1}}}'
  )))
  expect_false(n$push(list(event = "error", data = paste0(
    '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
  ))))
  expect_length(retried$events, 1L)
  expect_identical(retried$events[[1L]]$class, "overloaded")
  expect_identical(retried$events[[1L]]$status, 529L)
  expect_length(log$events, 0L)
  msg = n$finish()
  expect_identical(msg$stop_reason, "error")
  expect_identical(types_of(log$events), c("start", "error"))
  # the transport gives up on the retry (attempts used up): the provider's text is reported
  log2 = event_log()
  n2 = anthropic_normaliser(test_model(api), list(emit = log2$emit, retry = retried$emit))
  n2$push(list(event = "error", data = paste0(
    '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
  )))
  gave_up = structure(class = c("gptr_error_overloaded", "gptr_error_provider", "gptr_error",
                                "error", "condition"),
                      list(message = "The provider reported a retryable failure (overloaded).",
                           call = NULL, status = 529L))
  msg = n2$fail(gave_up)
  expect_identical(msg$error_message, "overloaded_error: Overloaded")
  expect_identical(log2$events[[2L]]$error$class, "overloaded")
  expect_identical(log2$events[[2L]]$error$status, 529L)
})

test_that("a spend-cap error is never retried (report 07 section 2.11)", {
  log = event_log()
  retried = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit, retry = retried$emit))
  done = n$push(list(event = "error", data = paste0(
    '{"type":"error","error":{"type":"rate_limit_error","message":"cap",',
    '"details":{"error_code":"enforced_spend_limit_reached"}}}'
  )))
  expect_true(done)
  expect_length(retried$events, 0L)
  expect_identical(log$events[[2L]]$error$class, "spend_cap")
})

test_that("fail() gives one error event, aborted when the run's signal says so", {
  log = event_log()
  signal = new.env()
  signal$aborted = TRUE
  n = anthropic_normaliser(test_model(api), list(emit = log$emit, signal = signal))
  cnd = structure(class = c("gptr_error_network", "gptr_error_provider", "gptr_error", "error",
                            "condition"),
                  list(message = "connection reset", call = NULL))
  msg = n$fail(cnd)
  expect_identical(msg$stop_reason, "aborted")
  expect_identical(log$events[[length(log$events)]]$reason, "aborted")
  expect_identical(log$events[[length(log$events)]]$error$class, "network")
  n$fail(cnd)
  n$finish()
  expect_identical(sum(types_of(log$events) %in% c("done", "error")), 1L)
})

test_that("fail() and message() never signal, even for a malformed condition (04 section 8.1)", {
  log = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit))
  msg = n$fail("not a condition object")
  expect_identical(msg$stop_reason, "error")
  expect_identical(types_of(log$events), c("start", "error"))
  expect_identical(log$events[[2L]]$error$class, "internal")
  expect_identical(n$message()$stop_reason, "error")
})

test_that("unparsable data ends the stream with an error event, never an R condition", {
  log = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit))
  expect_true(n$push(list(event = "content_block_delta", data = "{not json")))
  expect_identical(types_of(log$events), c("start", "error"))
  expect_identical(n$message()$stop_reason, "error")
})

test_that("40,000 text deltas are consumed in linear time (INFRA-23; skip on CRAN)", {
  skip_on_cran()
  n = anthropic_normaliser(test_model(api), list(emit = function(ev) NULL))
  n$push(list(event = "message_start", data = paste0(
    '{"type":"message_start","message":{"id":"m","usage":{"input_tokens":1}}}'
  )))
  n$push(list(event = "content_block_start", data = paste0(
    '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}'
  )))
  delta = list(event = "content_block_delta", data = paste0(
    '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"tok "}}'
  ))
  secs = system.time(for (i in seq_len(40000L)) n$push(delta))[["elapsed"]]
  n$push(list(event = "message_delta", data = paste0(
    '{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":9}}'
  )))
  n$push(list(event = "message_stop", data = '{"type":"message_stop"}'))
  expect_lt(secs, 5)
  expect_identical(nchar(n$message()$content[[1L]]$text), 160000L)
})

test_that("an event of an unexpected shape ends the stream with an error event, not a condition", {
  log = event_log()
  n = anthropic_normaliser(test_model(api), list(emit = log$emit))
  n$push(list(event = "content_block_start", data = paste0(
    '{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}'
  )))
  expect_true(n$push(list(event = "content_block_delta", data = paste0(
    '{"type":"content_block_delta","index":0,"delta":"not an object"}'
  ))))
  expect_identical(types_of(log$events), c("start", "text_start", "error"))
  expect_identical(log$events[[3L]]$error$class, "internal")
  expect_identical(n$finish()$stop_reason, "error")
  expect_identical(sum(types_of(log$events) %in% c("done", "error")), 1L)
})

test_that("push_parsed() accepts stream-event objects (the cli-claude reuse, 04 section 7.12)", {
  dir = sse_dir(api)
  path = file.path(dir, "thinking_tools.sse")
  evs = sse_splitter()$push(readBin(path, "raw", file.size(path)))
  log = event_log()
  cli = adp_fixture_model(api, dir)
  cli$type = "cli"
  n = anthropic_normaliser(cli, list(emit = log$emit))
  for (ev in evs) n$push_parsed(json_decode(ev$data))
  msg = n$finish()
  expect_golden(lapply(log$events, adp_golden_event), api, "thinking_tools.events.json")
  expect_identical(msg$route, "plan-cli")
  expect_identical(replay_case(api, anthropic_normaliser, "text")$message$route, "api")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-anthropic")'`
Expected: `[ FAIL 13 | WARN 0 | SKIP 0 | PASS 1 ]`, with errors such as ``object 'anthropic_normaliser' not found`` and ``could not find function "anthropic_normaliser"``.

- [ ] **Step 3: Write the implementation**

Create `R/provider-anthropic.R`:

```r
# The anthropic-messages adapter (P12) and the normaliser core shared by the four native
# adapters (anthropic-messages, openai-responses, openai-completions, google-generative-ai),
# plus check_adapter(), the check.adapter service behind gptr_check() for adapter specs.
# Contract: dev/spec/04-interface-contract.md sections 4.1-4.5, 7.12, 8.1 and IC-69/IC-71.
# The normaliser follows the verified prototypes of report 07 section 5.1 and report 03
# section 5.3 (verification logs applied: tool names up to 128 characters, mid-conversation
# system messages only after a user turn and before an assistant turn or the end, no
# ANTHROPIC_API_KEY and Bearer together, every string marked UTF-8 by the P01 constructors).
# Request bodies follow G4 section 3.7 (key order, breakpoints) and section 5.4 (bodies are
# concatenations of pieces serialised once per session through opts$memo).

# ---- shared normaliser core -----------------------------------------------------------------

#' A growable chunk buffer: deltas are appended to a preallocated list and joined once
#' @noRd
adp_buffer = function() {
  b = new.env(parent = emptyenv())
  b$v = vector("list", 32L)
  b$n = 0L
  b
}

#' Append one chunk to a buffer (the list doubles when full)
#'
#' The list is taken out of the environment and the binding cleared before the element is set:
#' `b$v[[n]] = x` on an environment passed as an argument copies the whole list on every call
#' (measured: 20,000 appends 1.7 s, quadratic), the take-out form 0.013 s (linear, INFRA-23).
#' @noRd
adp_buffer_add = function(b, x) {
  n = b$n + 1L
  v = b$v
  b$v = NULL
  if (n > length(v)) length(v) = 2L * length(v)
  v[[n]] = x
  b$v = v
  b$n = n
  invisible(NULL)
}

#' The joined text of a buffer
#' @noRd
adp_buffer_text = function(b) {
  if (b$n == 0L) return("")
  paste(unlist(b$v[seq_len(b$n)], use.names = FALSE), collapse = "")
}

#' The state of one normaliser: content slots, stop reason, usage and the terminal flag
#' @noRd
adp_state = function(model, opts) {
  st = new.env(parent = emptyenv())
  st$model = model
  st$emit_fun = opts$emit
  st$signal = opts$signal
  st$blocks = list()
  st$n = 0L
  st$started = FALSE
  st$terminal = FALSE
  st$deltas = FALSE
  st$pending = NULL
  st$stop_reason = NULL
  st$raw_stop = NULL
  st$error_message = NULL
  st$response_id = NULL
  st$response_model = NULL
  st$usage = list()
  st$final = NULL
  st
}

#' Emit one INFRA-02 event (contract section 4.5) through opts$emit
#' @noRd
adp_emit = function(st, type, ...) {
  if (is.function(st$emit_fun)) st$emit_fun(ev_new(type, ...))
  invisible(NULL)
}

#' Emit the start event once, before the first content event or the terminal event
#' @noRd
adp_start = function(st) {
  if (st$started) return(invisible(NULL))
  st$started = TRUE
  m = st$model
  adp_emit(st, "start", api = m$api, provider = m$provider, model = m$id, request_id = NULL,
           response_id = st$response_id)
}

#' Open a content slot (text, thinking, tool_call or opaque) and emit its start event
#' @noRd
adp_open = function(st, type, ...) {
  adp_start(st)
  b = new.env(parent = emptyenv())
  b$type = type
  b$buf = adp_buffer()
  b$done = FALSE
  b$block = NULL
  fields = list(...)
  for (k in names(fields)) assign(k, fields[[k]], envir = b)
  st$n = st$n + 1L
  st$blocks[[st$n]] = b
  i = st$n
  if (type %in% c("text", "thinking")) {
    adp_emit(st, paste0(type, "_start"), index = i)
  } else if (type == "tool_call") {
    adp_emit(st, "toolcall_start", index = i, id = b$id, name = b$name)
  }
  i
}

#' Append a delta to slot i and emit the matching *_delta event (empty deltas are dropped)
#' @noRd
adp_delta = function(st, i, text) {
  if (is.null(text) || !nzchar(text)) return(invisible(NULL))
  b = st$blocks[[i]]
  adp_buffer_add(b$buf, text)
  if (b$type == "opaque") return(invisible(NULL))
  st$deltas = TRUE
  if (b$type == "tool_call") {
    preview = NULL
    if (!is.null(b$pj)) {
      b$pj$push(text)
      preview = b$pj$preview()
    }
    adp_emit(st, "toolcall_delta", index = i, delta = text, preview = preview)
  } else {
    adp_emit(st, paste0(b$type, "_delta"), index = i, delta = text)
  }
}

#' Parse JSON text, NULL when it is empty or not valid JSON
#' @noRd
adp_json_try = function(text) {
  if (is.null(text) || !is.character(text) || !nzchar(text)) return(NULL)
  tryCatch(json_decode(text), error = function(e) NULL)
}

#' Is x a JSON object (a named list, possibly empty)?
#' @noRd
adp_is_object = function(x) is.list(x) && (length(x) == 0L || !is.null(names(x)))

#' A provider value as one string ("" for NULL, NA or a non-scalar)
#' @noRd
adp_chr = function(x) {
  if (is.null(x) || !is.atomic(x) || length(x) != 1L || is.na(x)) return("")
  as.character(x)
}

#' The content block of slot b, final or partial (contract section 4.1)
#' @noRd
adp_block = function(st, b) {
  m = st$model
  if (b$type == "text") {
    return(block_text(b$text_override %||% adp_buffer_text(b$buf), signature = b$signature))
  }
  if (b$type == "thinking") {
    sig = b$signature
    if (!is.null(sig) && !nzchar(sig)) sig = NULL
    return(block_thinking(b$text_override %||% adp_buffer_text(b$buf), signature = sig,
                          redacted = isTRUE(b$redacted), data = b$data,
                          origin = list(api = m$api, provider = m$provider, model = m$id)))
  }
  if (b$type == "tool_call") {
    raw_keep = NULL
    if (!is.null(b$args)) {
      args = b$args
    } else {
      raw = b$raw_override %||% adp_buffer_text(b$buf)
      parsed = adp_json_try(raw)
      if (!nzchar(raw)) {
        args = json_obj()
      } else if (adp_is_object(parsed)) {
        args = parsed
      } else {
        args = json_obj()
        raw_keep = raw
      }
    }
    if (length(args) == 0L) args = json_obj()
    id = adp_chr(b$id)
    if (!nzchar(id)) id = paste0("call_", b$slot %||% 0L)
    name = adp_chr(b$name)
    if (!nzchar(name)) name = "unknown_tool"
    return(block_tool_call(id, name, args, raw_arguments = raw_keep,
                           thought_signature = b$thought_signature))
  }
  if (is.null(b$json)) return(NULL)
  block_opaque(provider = m$provider, api = m$api, model = m$id, json = b$json)
}

#' Close slot i: build its final block and emit the *_end event
#' @noRd
adp_close = function(st, i) {
  b = st$blocks[[i]]
  if (b$done) return(invisible(b$block))
  b$slot = i
  b$block = adp_block(st, b)
  b$done = TRUE
  if (b$type == "tool_call") {
    adp_emit(st, "toolcall_end", index = i, block = b$block)
  } else if (b$type %in% c("text", "thinking")) {
    adp_emit(st, paste0(b$type, "_end"), index = i, block = b$block)
  }
  invisible(b$block)
}

#' Finalise an opaque slot from its JSON text (no event: opaque data is never streamed)
#' @noRd
adp_set_opaque = function(st, i, json) {
  b = st$blocks[[i]]
  b$json = json
  b$slot = i
  b$block = adp_block(st, b)
  b$done = TRUE
  invisible(b$block)
}

#' The usage record of contract section 4.3 from the provider-reported numbers, with cost
#' @noRd
adp_usage = function(st) {
  u = st$usage
  num = function(x) {
    if (is.null(x) || !length(x) || is.na(x[[1L]])) 0 else as.numeric(x[[1L]])
  }
  rec = usage_new(input = num(u$input), output = num(u$output), cache_read = num(u$cache_read),
                  cache_write_5m = num(u$cache_write_5m), cache_write_1h = num(u$cache_write_1h),
                  reasoning = num(u$reasoning))
  if (!is.null(st$model$prices)) {
    rec = tryCatch(usage_cost(rec, st$model), error = function(e) rec)
  }
  rec
}

#' The route of a model's messages (04 section 4.2): `plan-cli` for CLI models (P20 reuses the
#' Anthropic normaliser), `system-one` for classifiers, else `api`
#' @noRd
adp_route = function(model) {
  switch(model$type %||% "chat", cli = "plan-cli", classifier = "system-one", "api")
}

#' The current assistant message (materialised on demand, never per delta)
#' @noRd
adp_message = function(st) {
  if (!is.null(st$final)) return(st$final)
  m = st$model
  content = list()
  for (i in seq_len(st$n)) {
    b = st$blocks[[i]]
    b$slot = i
    blk = if (b$done) b$block else adp_block(st, b)
    if (!is.null(blk)) content[[length(content) + 1L]] = blk
  }
  msg_assistant(content, api = m$api, provider = m$provider, model = m$id, usage = adp_usage(st),
                stop_reason = st$stop_reason %||% "stop", response_id = st$response_id,
                response_model = st$response_model, error_message = st$error_message,
                raw_stop_reason = st$raw_stop, route = adp_route(m))
}

#' Emit the one terminal error event with the partial message
#' @noRd
adp_error = function(st, message, class = "provider", status = NA_integer_, retry_after = NULL,
                     aborted = FALSE) {
  if (st$terminal) return(st$final)
  if (length(status) != 1L || is.na(status)) status = NULL
  st$stop_reason = if (aborted) "aborted" else "error"
  st$error_message = message
  m = st$model
  msg = tryCatch(adp_message(st), error = function(e) {
    msg_assistant(list(), api = m$api, provider = m$provider, model = m$id,
                  stop_reason = st$stop_reason, error_message = message, route = adp_route(m))
  })
  st$final = msg
  st$terminal = TRUE
  adp_start(st)
  adp_emit(st, "error", reason = st$stop_reason, message = msg,
           error = list(class = class, status = status, request_id = NULL,
                        retry_after = retry_after))
  msg
}

#' Close open slots and emit the terminal event: done, or error for an error stop reason
#' @noRd
adp_done = function(st) {
  if (st$terminal) return(st$final)
  for (i in seq_len(st$n)) {
    if (!st$blocks[[i]]$done && st$blocks[[i]]$type != "opaque") adp_close(st, i)
  }
  if (is.null(st$stop_reason)) {
    return(adp_error(st, "The stream ended without a stop reason.", class = "network"))
  }
  if (st$stop_reason %in% c("error", "aborted")) {
    return(adp_error(st, st$error_message %||% "The provider reported an error.",
                     aborted = identical(st$stop_reason, "aborted")))
  }
  msg = adp_message(st)
  st$final = msg
  st$terminal = TRUE
  adp_start(st)
  adp_emit(st, "done", reason = msg$stop_reason, message = msg, usage = msg$usage)
  msg
}

#' A failure seen inside the stream: ask the transport to retry while no delta was committed
#' (04 section 8.1, `retry(info)`), otherwise end the stream with the error event
#' @noRd
adp_stream_error = function(st, opts, message, class, status = NA_integer_, retry_after = NULL,
                            retryable = FALSE) {
  if (retryable && !st$deltas && is.function(opts$retry)) {
    st$pending = list(message = message, class = class, status = status,
                      retry_after = retry_after)
    opts$retry(list(class = class, status = status, retry_after = retry_after))
    return(FALSE)
  }
  adp_error(st, message, class = class, status = status, retry_after = retry_after)
  TRUE
}

#' End of input after a retry request the transport did not act on
#' @noRd
adp_finish_pending = function(st) {
  p = st$pending
  adp_error(st, p$message, class = p$class, status = p$status, retry_after = p$retry_after)
}

#' The normaliser's fail(cnd): a transport failure becomes the one terminal error event. After
#' a retry request the transport gave up on, the provider's own error text is reported
#' @noRd
adp_fail = function(st, cnd) {
  if (st$terminal) return(st$final)
  if (!is.null(st$pending) && !isTRUE(st$signal$aborted)) return(adp_finish_pending(st))
  cls = sub("^gptr_error_", "", class(cnd)[[1L]])
  adp_error(st, conditionMessage(cnd), class = cls, status = cnd$status %||% NA_integer_,
            retry_after = cnd$retry_after, aborted = isTRUE(st$signal$aborted))
}

#' Run one normaliser step; an R error inside it ends the stream with the one terminal error
#' event instead of escaping (04 section 8.1: no R condition after `start`)
#' @noRd
adp_guard = function(st, f) {
  force(f)
  function(...) {
    tryCatch(f(...), error = function(e) {
      adp_error(st, paste0("The adapter could not process the stream: ", conditionMessage(e)),
                class = "internal")
      TRUE
    })
  }
}

#' The normaliser list of contract section 8.1 (push, finish, fail, message[, push_parsed]);
#' no function of it signals an R condition (an error becomes the one terminal error event, and
#' message() falls back to an empty error message)
#' @noRd
adp_normaliser = function(st, push, finish, push_parsed = NULL) {
  out = list(push = adp_guard(st, push),
             finish = function() {
               tryCatch(finish(), error = function(e) {
                 adp_error(st, paste0("The adapter could not finish the stream: ",
                                      conditionMessage(e)), class = "internal")
               })
             },
             fail = function(cnd) {
               tryCatch(adp_fail(st, cnd), error = function(e) {
                 adp_error(st, paste0("The adapter could not record a transport failure: ",
                                      conditionMessage(e)), class = "internal")
               })
             },
             message = function() {
               tryCatch(adp_message(st), error = function(e) {
                 m = st$model
                 msg_assistant(list(), api = m$api, provider = m$provider, model = m$id,
                               stop_reason = "error",
                               error_message = paste0("The partial message could not be built: ",
                                                      conditionMessage(e)),
                               route = adp_route(m))
               })
             })
  if (!is.null(push_parsed)) out$push_parsed = adp_guard(st, push_parsed)
  out
}

# ---- golden projection and fixture replay (tests and check_adapter()) -----------------------

#' Golden projection of a content block: the contract fields only (04 sections 4.1, 12.4)
#' @noRd
adp_golden_block = function(b) {
  keep = c("type", "text", "thinking", "signature", "redacted", "data", "id", "name", "arguments",
           "raw_arguments", "thought_signature", "json")
  out = b[intersect(keep, names(b))]
  if (identical(out$redacted, FALSE)) out$redacted = NULL
  out[!vapply(out, is.null, logical(1))]
}

#' Golden projection of an event: volatile fields (ts, session, run, preview) and the terminal
#' message are left out; the final message is compared on its own
#' @noRd
adp_golden_event = function(ev) {
  keep = c("type", "index", "id", "name", "delta", "reason", "response_id")
  out = ev[intersect(keep, names(ev))]
  out = out[!vapply(out, is.null, logical(1))]
  if (!is.null(ev$block)) out$block = adp_golden_block(ev$block)
  if (!is.null(ev$error)) out$error = list(class = ev$error$class, status = ev$error$status)
  out
}

#' Golden projection of a final assistant message (cost left out: it depends on prices)
#' @noRd
adp_golden_message = function(m) {
  u = m$usage
  out = list(stop_reason = m$stop_reason, raw_stop_reason = m$raw_stop_reason,
             error_message = m$error_message, response_id = m$response_id,
             response_model = m$response_model, content = lapply(m$content, adp_golden_block),
             usage = list(input = u$input, output = u$output, cache_read = u$cache_read,
                          cache_write_5m = u$cache_write_5m, cache_write_1h = u$cache_write_1h,
                          reasoning = u$reasoning, total = u$total))
  out[!vapply(out, is.null, logical(1))]
}

#' Deterministic pseudo-random chunk sizes (1-17 bytes) from hash bits; RNG-free (IC-61)
#' @noRd
adp_chunk_sizes = function(key) {
  h = hash_sha256(key)
  as.integer(strtoi(substring(h, seq(1L, 63L, 2L), seq(2L, 64L, 2L)), 16L) %% 17L) + 1L
}

#' Split raw bytes into chunks of the given sizes (recycled)
#' @noRd
adp_split_raw = function(bytes, sizes) {
  out = list()
  pos = 1L
  k = 1L
  n = length(bytes)
  while (pos <= n) {
    end = min(n, pos + sizes[[(k - 1L) %% length(sizes) + 1L]] - 1L)
    out[[length(out) + 1L]] = bytes[pos:end]
    pos = end + 1L
    k = k + 1L
  }
  out
}

#' Events of a splitter's flush(): NULL, one event, or a list of events
#' @noRd
adp_flushed = function(fl) {
  if (is.null(fl) || !length(fl)) return(list())
  if (!is.null(names(fl))) list(fl) else fl
}

#' Replay fixture bytes through an adapter's normaliser in chunks of the given sizes, the way
#' provider_stream() does (P05): splitter -> push(); end of input -> finish()
#' @noRd
adp_replay = function(adapter, model, bytes, sizes) {
  log = new.env(parent = emptyenv())
  log$events = list()
  emit = function(ev) log$events[[length(log$events) + 1L]] = ev
  signal = new.env(parent = emptyenv())
  signal$aborted = FALSE
  opts = list(emit = emit, base_url = "http://127.0.0.1:1", signal = signal,
              send = function(obj) invisible(NULL))
  res = tryCatch({
    n = adapter$parse(model, opts)
    chunks = adp_split_raw(bytes, sizes)
    if (identical(adapter$transport, "http_json")) {
      n$push(list(data = raw_to_utf8(bytes), status = 200L, headers = list()))
    } else if (adapter$transport %in% c("http_ndjson", "process_jsonl")) {
      sp = ndjson_splitter()
      lines = character()
      for (chunk in chunks) lines = c(lines, sp$push(chunk))
      lines = c(lines, sp$flush())
      for (ln in lines[nzchar(lines)]) {
        if (identical(adapter$transport, "process_jsonl")) {
          n$push(list(data = ln, obj = json_decode(ln)))
        } else {
          n$push(list(data = ln))
        }
      }
    } else {
      sp = sse_splitter()
      for (chunk in chunks) for (ev in sp$push(chunk)) n$push(ev)
      for (ev in adp_flushed(sp$flush())) n$push(ev)
    }
    list(message = n$finish(), condition = NULL)
  }, error = function(e) list(message = NULL, condition = e))
  c(res, list(events = log$events))
}

#' The fixture model record (contract section 4.9 shape); `<dir>/model.json` overrides fields
#' @noRd
adp_fixture_model = function(api, dir = NULL) {
  m = list(ref = "fixture/fixture-1", provider = "fixture", id = "fixture-1",
           name = "Fixture model", family = "fixture", api = api, type = "chat",
           release_date = NA_character_, context = 200000, max_output = 8192, reasoning = TRUE,
           thinking_levels = c("off", "low", "medium", "high"), thinking = NULL,
           input = c("text", "image"), tool_call = TRUE, structured_output = TRUE,
           cache_min = NA_real_,
           capabilities = list(mid_system = TRUE, tool_addition = TRUE, images_in_results = TRUE,
                               adaptive_thinking = TRUE, effort = TRUE),
           aliases = character(), status = "active", local = TRUE)
  f = if (is.null(dir)) "" else file.path(dir, "model.json")
  if (nzchar(f) && file.exists(f)) {
    over = json_decode(read_utf8(f)$text)
    for (k in names(over)) m[[k]] = over[[k]]
  }
  m
}

# ---- anthropic-messages: normaliser -----------------------------------------------------------

#' Anthropic stop reason -> gptr stop reason (contract section 4.2; report 07 section 2.10)
#' @noRd
anthropic_stop = function(reason) {
  switch(reason,
         end_turn = , stop_sequence = "stop",
         max_tokens = , model_context_window_exceeded = "length",
         tool_use = "tool_use", pause_turn = "pause", refusal = "refusal",
         "error")
}

#' Anthropic error type -> class suffix (04 section 2.2), HTTP status and retryability
#' (report 07 section 2.11; the spend cap is never retried)
#' @noRd
anthropic_error_info = function(err) {
  type = err$type %||% ""
  if (identical(err$details$error_code, "enforced_spend_limit_reached")) {
    return(list(class = "spend_cap", status = 429L, retry = FALSE))
  }
  switch(type,
         overloaded_error = list(class = "overloaded", status = 529L, retry = TRUE),
         api_error = list(class = "overloaded", status = 500L, retry = TRUE),
         timeout_error = list(class = "overloaded", status = 504L, retry = TRUE),
         rate_limit_error = list(class = "rate_limit", status = 429L, retry = TRUE),
         authentication_error = list(class = "auth", status = 401L, retry = FALSE),
         permission_error = list(class = "auth", status = 403L, retry = FALSE),
         billing_error = list(class = "provider", status = 402L, retry = FALSE),
         not_found_error = list(class = "provider", status = 404L, retry = FALSE),
         request_too_large = list(class = "provider", status = 413L, retry = FALSE),
         invalid_request_error = list(class = "provider", status = 400L, retry = FALSE),
         list(class = "provider", status = NA_integer_, retry = FALSE))
}

#' Copy Anthropic usage fields into the normaliser state (message_start, message_delta).
#' `[[` only: `$` would let `cache_creation` match `cache_creation_input_tokens` (07 5.2)
#' @noRd
anthropic_usage = function(st, u) {
  if (is.null(u)) return(invisible(NULL))
  if (!is.null(u[["input_tokens"]])) st$usage$input = u[["input_tokens"]]
  if (!is.null(u[["output_tokens"]])) st$usage$output = u[["output_tokens"]]
  if (!is.null(u[["cache_read_input_tokens"]])) {
    st$usage$cache_read = u[["cache_read_input_tokens"]]
  }
  cc = u[["cache_creation"]]
  if (!is.null(cc)) {
    st$usage$cache_write_5m = cc[["ephemeral_5m_input_tokens"]] %||% 0
    st$usage$cache_write_1h = cc[["ephemeral_1h_input_tokens"]] %||% 0
  } else if (!is.null(u[["cache_creation_input_tokens"]])) {
    st$usage$cache_write_5m = u[["cache_creation_input_tokens"]]
    st$usage$cache_write_1h = 0
  }
  think = u[["output_tokens_details"]][["thinking_tokens"]]
  if (!is.null(think)) st$usage$reasoning = think
  invisible(NULL)
}

#' The Anthropic SSE normaliser (contract sections 7.12 and 8.1)
#'
#' `push(ev)` takes decoded SSE events, `push_parsed(obj)` already-parsed stream-event objects
#' (the `stream_event` lines of the claude CLI, P20); `finish()`, `fail(cnd)` and `message()`
#' as in section 8.1. Adapted from the verified accumulator of report 07 section 5.1.
#' @param model A model record (contract section 4.9).
#' @param opts The adapter options of contract section 8.1 (`emit`, `retry`, `signal`).
#' @return A list of functions `push`, `push_parsed`, `finish`, `fail`, `message`.
#' @noRd
anthropic_normaliser = function(model, opts) {
  st = adp_state(model, opts)
  map = new.env(parent = emptyenv())
  seen = new.env(parent = emptyenv())
  seen$start = FALSE

  on_block_start = function(obj) {
    cb = obj$content_block
    type = cb$type %||% ""
    i = if (type == "text") {
      adp_open(st, "text")
    } else if (type == "thinking") {
      adp_open(st, "thinking", signature = cb$signature %||% "")
    } else if (type == "redacted_thinking") {
      adp_open(st, "thinking", redacted = TRUE, data = cb$data, signature = "")
    } else if (type == "tool_use") {
      adp_open(st, "tool_call", id = cb$id, name = cb$name, pj = partial_json())
    } else {
      adp_open(st, "opaque", raw_block = cb)
    }
    assign(as.character(obj$index), i, envir = map)
    if (type == "text") adp_delta(st, i, cb$text)
    if (type == "thinking") adp_delta(st, i, cb$thinking)
    FALSE
  }

  on_block_delta = function(obj) {
    i = map[[as.character(obj$index)]]
    if (is.null(i)) return(FALSE)
    b = st$blocks[[i]]
    d = obj$delta
    dt = d$type %||% ""
    if (dt == "text_delta" && b$type == "text") {
      adp_delta(st, i, d$text)
    } else if (dt == "thinking_delta" && b$type == "thinking") {
      adp_delta(st, i, d$thinking)
    } else if (dt == "signature_delta" && b$type == "thinking") {
      b$signature = paste0(b$signature %||% "", d$signature)
    } else if (dt == "input_json_delta" && b$type %in% c("tool_call", "opaque")) {
      adp_delta(st, i, d$partial_json)
    }
    FALSE
  }

  on_block_stop = function(obj) {
    i = map[[as.character(obj$index)]]
    if (is.null(i)) return(FALSE)
    b = st$blocks[[i]]
    if (b$type == "opaque") {
      cb = b$raw_block
      input = adp_json_try(adp_buffer_text(b$buf))
      if (adp_is_object(input)) cb$input = if (length(input)) input else json_obj()
      adp_set_opaque(st, i, json_encode(cb))
    } else {
      adp_close(st, i)
    }
    FALSE
  }

  on_message_delta = function(obj) {
    reason = obj$delta$stop_reason
    if (!is.null(reason)) {
      st$raw_stop = reason
      st$stop_reason = anthropic_stop(reason)
      if (identical(reason, "refusal")) {
        st$error_message = obj$delta$stop_details$explanation %||% "The model declined to answer."
      } else if (identical(st$stop_reason, "error")) {
        st$error_message = paste0("Provider stopped with: ", reason)
      }
    }
    anthropic_usage(st, obj$usage)
    FALSE
  }

  on_error = function(obj) {
    info = anthropic_error_info(obj$error)
    msg = paste0(obj$error$type %||% "error", ": ", obj$error$message %||% "unknown error")
    adp_stream_error(st, opts, msg, class = info$class, status = info$status,
                     retryable = info$retry)
  }

  push_parsed = function(obj) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    type = obj$type %||% ""
    if (type == "message_start") {
      seen$start = TRUE
      m = obj$message
      st$response_id = m$id
      if (!is.null(m$model) && !identical(m$model, model$id)) st$response_model = m$model
      anthropic_usage(st, m$usage)
      return(FALSE)
    }
    if (type == "content_block_start") return(on_block_start(obj))
    if (type == "content_block_delta") return(on_block_delta(obj))
    if (type == "content_block_stop") return(on_block_stop(obj))
    if (type == "message_delta") return(on_message_delta(obj))
    if (type == "message_stop") {
      adp_done(st)
      return(TRUE)
    }
    if (type == "error") return(on_error(obj))
    FALSE
  }

  push = function(ev) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    data = ev$data %||% ""
    if (!nzchar(data)) return(FALSE)
    obj = adp_json_try(data)
    if (!adp_is_object(obj)) {
      adp_error(st, paste0("Could not parse an Anthropic stream event: ", substr(data, 1L, 200L)))
      return(TRUE)
    }
    if (identical(ev$event, "error")) obj$type = "error"
    push_parsed(obj)
  }

  finish = function() {
    if (st$terminal) return(st$final)
    if (!is.null(st$pending)) return(adp_finish_pending(st))
    if (!seen$start) {
      return(adp_error(st, "The Anthropic stream ended before any event.", class = "network"))
    }
    adp_error(st, "The Anthropic stream ended before message_stop.", class = "network")
  }

  adp_normaliser(st, push, finish, push_parsed)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-anthropic")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 99 ]` (the linear-time test runs because `devtools::test()` sets `NOT_CRAN=true`; under `R CMD check --as-cran` it is one skip).

- [ ] **Step 5: Commit**

```bash
git add R/provider-anthropic.R tests/testthat/test-provider-anthropic.R tests/testthat/fixtures/sse/make_fixtures.R tests/testthat/fixtures/sse/replay_helpers.R tests/testthat/fixtures/sse/anthropic-messages
git commit -m "feat(provider): add the shared normaliser core and the anthropic normaliser"
```

---

### Task 2: Anthropic request bodies and `builtin:anthropic`

**Files:**
- Modify: `R/provider-anthropic.R` (append)
- Modify: `tests/testthat/fixtures/sse/replay_helpers.R` (append)
- Test: `tests/testthat/test-provider-anthropic.R` (append)

**Interfaces:**
- Consumes: `json_verbatim(text)`, `hash_xxh128(x)`, `gptr_has_human()`, `on_load(expr)` (P01); `gptr_adapter(api, transport = c(...), build = NULL, parse = NULL, stream = NULL, classify = NULL, capabilities = list())`, `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)` (P02); `provider_get(id)` (P05, for the provider record's non-secret `headers`). Tests also use `msg_user()`, `msg_tool_result()`, `msg_operator(kind, text, tool_add = NULL, origin_text = NULL, timestamp = NULL)`, `block_context(kind, text, attrs = list(), anchor = FALSE)`, `block_image(data, mime = "image/png", source = "plot", width = NULL, height = NULL)`, `local_gptr_options()`, `local_mock_server(scenario, ..., .env = parent.frame())` (P01); `gptr_register()`, `gptr_provider()`, `gptr_tool()`, `registry_get(kind, name, session = NULL)` (P02); `reactor_http()` (mocked), `reactor_task(fn, run = NULL)`, `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)` (P04); `adapter_get(api)`, `model_resolve(ref, strict = TRUE)`, `provider_stream(model, context, opts, emit, done, run = NULL)` (P05); `session_new(model, mode, home = NULL, ...)`, `session_run(s, input, opts = list())` (P06); the `default` `cache_policy` record with `plan(parts, caps, session)` (P07).
- Produces: `anthropic_build(model, context, opts)` (the adapter's `build`), `anthropic_caps()`, `builtin_anthropic(gptr)` and the registered adapter `anthropic-messages` (`transport = "http_sse"`, `build = anthropic_build`, `parse = anthropic_normaliser`, the capabilities of the Global Constraints table). Request helpers shared by Tasks 5, 7 and 9: `adp_model_cap(model, name, default = FALSE)`, `adp_same_model(msg, model)`, `adp_images_ok(model)`, `adp_image_note()`, `adp_header_secret(handle, prefix = "")`, `adp_url(base, path)`, `adp_provider_headers(model)`, `adp_returns_instruction(schema)`, `adp_memo(opts, key, fun)`, `adp_msg_key(msg)`, `adp_sanitize_id(id, max = 64L)`, `adp_tools_json(opts, api, tools_json, convert)`, `adp_has_tool_calls(msgs)`, `adp_anchor_index(msgs)`, `adp_operator_text(m)`, `adp_level_effort(level)`, `adp_budget(level)`, `adp_body(head, extra, key, elements)`, `adp_cache_plan(context)`, `adp_forced(tc)`, `adp_forced_ok(model, caps)`.

Body rules (G4 sections 2.3, 3.7, 3.8, 5.4 `layout.R`; report 07 sections 2.3-2.8 and its verification log): key order `model`, `max_tokens`, `stream`, `cache_control` (the automatic tail breakpoint, `ttl = "1h"` when the plan's `tail_ttl` is `"1h"`), `thinking`, `output_config`, `tool_choice`, the declared request params, `tools` (the frozen array verbatim), `system` (`[T0 with BP1 1 h, T1]`), `messages` last. BP2 (1 h) goes on the anchored project block when the plan names `project`, else on T1 when the plan names `t1`. Each message element is serialised once per session through `opts$memo`. Consecutive tool results become one user message with the `tool_result` blocks first; tool-result images are native `image` blocks (acceptance 3). Signed thinking, redacted thinking and opaque blocks replay byte for byte only to the model that produced them; foreign thinking becomes text. A run of consecutive operator messages becomes ONE message (report 07 section 2.3: a mid-conversation system message must follow a user message and be last or followed by an assistant turn, so two system messages never follow each other): a mid-conversation `system` message only on models with `mid_system` and only when the run follows a user turn and precedes an assistant turn or the end; its `tool_add` declarations become `tool_addition` blocks with the `inline-tools-2026-09-15` beta; elsewhere the run is user text. Adaptive models get `thinking: {type: "adaptive", display}` (`summarized` when a human watches, else `omitted`) and `output_config.effort`; budget models (Haiku 4.5) get `enabled` with a budget below `max_tokens` and the interleaved-thinking beta. `temperature` is sent only to models without adaptive thinking and without a thinking configuration (non-default values are a 400 on every 5.x model). `returns` uses `output_config.format` (`json_schema`) when the model supports structured output, otherwise an instruction appended at the tail (a system message right after a user turn on `mid_system` models, so a trailing operator run is then sent as user text, else a user message); a forced `tool_choice` is sent only when the model allows it and neither thinking nor `returns` is active.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/fixtures/sse/replay_helpers.R`:

```r
# ---- request contexts (04 section 8.1) ---------------------------------------------------------

# The frozen tool array in the Anthropic shape (04 section 9.2): read and r
tools_json_fixture = function() {
  json_verbatim(paste0(
    '[{"name":"read","description":"Read a file.","input_schema":{"type":"object",',
    '"required":["path"],"properties":{"path":{"type":"string"}}}},',
    '{"name":"r","description":"Run R code.","input_schema":{"type":"object",',
    '"required":["code"],"properties":{"code":{"type":"string"}}}}]'
  ))
}

# The first user message: the anchored project block, the environment block, the prompt
first_message = function(prompt = "How many rows does d have?") {
  msg_user(list(block_context("project_instructions", "Use data.table.",
                              attrs = list(path = "AGENTS.md"), anchor = TRUE),
                block_context("environment", "R 4.4.3 on macOS"),
                block_text(prompt)), timestamp = 1)
}

# A request context of 04 section 8.1
ctx_fixture = function(messages, params = list(), cache_plan = NULL, t1 = "T1 catalogs.") {
  p = list(max_tokens = 1024L, thinking = NULL, effort = NULL, tool_choice = "auto",
           returns = NULL, temperature = NULL)
  for (k in names(params)) p[k] = list(params[[k]])
  list(system = list(t0 = "T0 static sections.", t1 = t1), tools_json = tools_json_fixture(),
       tools = list(), messages = messages,
       cache_plan = cache_plan %||% list(anchors = c("t0", "project"), tail_ttl = "5m",
                                         key = "gptr:0123456789ab"),
       params = p, session_id = "s0123456789", request_id = "q0123456789ab")
}

# The cache plan the registered default cache_policy (P07, prompt-cache.R) gives an adapter
default_plan = function(api, project = TRUE) {
  policy = registry_get("cache_policy", "default")
  testthat::skip_if(is.null(policy), "the default cache_policy of builtin:prompt is not loaded")
  parts = list(t0 = "T0 static sections.", t1 = "T1 catalogs.", tools_json = "[]",
               project = project, n = 1L)
  policy$plan(parts, adapter_get(api)$capabilities, NULL)
}

# A secret handle of the 04 section 5.9 shape, holding no value
fake_handle = function(name) {
  structure(list(id = paste0(name, "#abc123"), name = name, fp = "abc123", origin = NULL),
            class = "gptr_secret")
}

# A 1 x 1 PNG as base64
png_b64 = function() {
  paste0("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJ",
         "RU5ErkJggg==")
}

# ---- scripted wire: SSE bodies through the real adapter, run loop and reactor -----------------

# Replace reactor_http() (P04) so that request k receives bodies[[k]] (the last repeats) through
# reactor_task(); every request spec is kept in wire$requests. No socket is opened.
local_scripted_wire = function(bodies, .env = parent.frame()) {
  wire = new.env(parent = emptyenv())
  wire$bodies = bodies
  wire$requests = list()
  scripted_http = function(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL,
                           provider = NULL, retry = NULL) {
    k = length(wire$requests) + 1L
    wire$requests[[k]] = spec
    body = wire$bodies[[min(k, length(wire$bodies))]]
    reactor_task(function() {
      if (is.function(on_headers)) on_headers(200L, list(`content-type` = "text/event-stream"))
      on_bytes(charToRaw(body))
      on_done(200L, list())
      FALSE
    })
  }
  testthat::local_mocked_bindings(reactor_http = scripted_http, .env = .env)
  wire
}

# One SSE event as text
sse_event = function(event, data) paste0("event: ", event, "\n", "data: ", data, "\n\n")

# An Anthropic stream with one tool call (stop_reason tool_use)
anthropic_sse_tool = function(id, name, json) {
  paste0(
    sse_event("message_start", paste0('{"type":"message_start","message":{"id":"msg_w1",',
                                      '"model":"scripted-1","usage":{"input_tokens":20,',
                                      '"output_tokens":1}}}')),
    sse_event("content_block_start", paste0('{"type":"content_block_start","index":0,',
                                            '"content_block":{"type":"tool_use","id":"', id,
                                            '","name":"', name, '","input":{}}}')),
    sse_event("content_block_delta", paste0('{"type":"content_block_delta","index":0,',
                                            '"delta":{"type":"input_json_delta",',
                                            '"partial_json":', json_encode(json), "}}")),
    sse_event("content_block_stop", '{"type":"content_block_stop","index":0}'),
    sse_event("message_delta", paste0('{"type":"message_delta","delta":{"stop_reason":',
                                      '"tool_use"},"usage":{"output_tokens":5}}')),
    sse_event("message_stop", '{"type":"message_stop"}')
  )
}

# An Anthropic stream with one text block (stop_reason end_turn)
anthropic_sse_text = function(text) {
  paste0(
    sse_event("message_start", paste0('{"type":"message_start","message":{"id":"msg_w2",',
                                      '"model":"scripted-1","usage":{"input_tokens":30,',
                                      '"output_tokens":1}}}')),
    sse_event("content_block_start", paste0('{"type":"content_block_start","index":0,',
                                            '"content_block":{"type":"text","text":""}}')),
    sse_event("content_block_delta", paste0('{"type":"content_block_delta","index":0,',
                                            '"delta":{"type":"text_delta","text":',
                                            json_encode(text), "}}")),
    sse_event("content_block_stop", '{"type":"content_block_stop","index":0}'),
    sse_event("message_delta", paste0('{"type":"message_delta","delta":{"stop_reason":',
                                      '"end_turn"},"usage":{"output_tokens":6}}')),
    sse_event("message_stop", '{"type":"message_stop"}')
  )
}

# A scripted provider record (offline, local, no key, IC-45) for an api, registered for the
# calling test
local_scripted_provider = function(api, structured_output = TRUE, .env = parent.frame()) {
  spec = gptr_provider("scripted", api = api, base_url = "http://127.0.0.1:9", auth = NULL,
                       models = list(list(id = "scripted-1", name = "Scripted",
                                          context = 200000, max_output = 4096,
                                          reasoning = FALSE,
                                          structured_output = structured_output,
                                          input = c("text", "image"), tool_call = TRUE)),
                       local = TRUE, offline = TRUE)
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  invisible(spec)
}

# A `count` tool registered for the calling test; it answers "32"
local_count_tool = function(.env = parent.frame()) {
  off = gptr_register(gptr_tool("count", "Count the rows of the data.",
                                parameters = list(type = "object", properties = json_obj()),
                                execute = function(input, ctx) "32"))
  withr::defer(off(), envir = .env)
  invisible(NULL)
}

# The `returns =` schema of the INFRA-25 runs
count_schema = function() {
  list(type = "object", required = I("n"), properties = list(n = list(type = "integer")))
}

# ---- the base-R mock server (P01's local_mock_server(), skips on CRAN) -------------------------

# Stream one request to the mock server through provider_stream() and the reactor; with
# `abort_after`, the run's signal is set after that many text deltas
mock_stream = function(srv, context = NULL, abort_after = NULL) {
  off = gptr_register(srv$provider)
  on.exit(off(), add = TRUE)
  model = srv$provider$models[[1L]]
  log = event_log()
  out = new.env(parent = emptyenv())
  out$message = NULL
  signal = new.env(parent = emptyenv())
  signal$aborted = FALSE
  signal$reason = NULL
  emit = function(ev) {
    log$emit(ev)
    if (!is.null(abort_after) && sum(types_of(log$events) == "text_delta") >= abort_after) {
      signal$aborted = TRUE
      signal$reason = "user"
    }
  }
  provider_stream(model, context %||% ctx_fixture(list(msg_user("hello", timestamp = 1))),
                  list(signal = signal), emit = emit, done = function(msg) out$message = msg)
  reactor_pump(until = function() !is.null(out$message), timeout = 30)
  list(events = log$events, types = types_of(log$events), message = out$message)
}
```

Append to `tests/testthat/test-provider-anthropic.R`:

```r
# ---- the request body and the built-in (Task 2) ------------------------------------------------

anthropic_turn2 = function(model) {
  asst = msg_assistant(list(block_text("Checking."),
                            block_tool_call("toolu_01A", "r", list(code = "nrow(d)"))),
                       api = api, provider = model$provider, model = model$id,
                       stop_reason = "tool_use", timestamp = 2)
  # first_message() comes from replay_helpers.R, sourced at run time where lintr cannot see it
  first = first_message() # nolint: object_usage_linter.
  list(first, asst, msg_tool_result("toolu_01A", "r", "[1] 32", timestamp = 3))
}

test_that("anthropic breakpoints follow G4 section 3.7: T0 and the project block 1 h, auto tail", {
  model = test_model(api)
  req = anthropic_build(model, ctx_fixture(list(first_message())), list())
  body = json_decode(req$body)
  expect_identical(names(body), c("model", "max_tokens", "stream", "cache_control", "thinking",
                                  "tools", "system", "messages"))
  expect_equal(body$cache_control, list(type = "ephemeral"))
  expect_equal(body$system[[1L]]$cache_control, list(type = "ephemeral", ttl = "1h"))
  expect_null(body$system[[2L]]$cache_control)
  project = body$messages[[1L]]$content[[1L]]
  expect_match(project$text, "<project_instructions", fixed = TRUE)
  expect_equal(project$cache_control, list(type = "ephemeral", ttl = "1h"))
  expect_null(body$messages[[1L]]$content[[2L]]$cache_control)
  expect_identical(lengths(regmatches(req$body, gregexpr("cache_control", req$body))), 3L)
  plan = list(anchors = c("t0", "project"), tail_ttl = "1h", key = "gptr:0123456789ab")
  body_1h = json_decode(anthropic_build(model, ctx_fixture(list(first_message()),
                                                           cache_plan = plan), list())$body)
  expect_equal(body_1h$cache_control, list(type = "ephemeral", ttl = "1h"))
})

test_that("the default cache policy of prompt-cache.R drives the breakpoints (acceptance 4)", {
  plan = default_plan(api)
  expect_identical(plan$anchors, c("t0", "project"))
  body = json_decode(anthropic_build(test_model(api), ctx_fixture(list(first_message()),
                                                                  cache_plan = plan),
                                     list())$body)
  expect_equal(body$system[[1L]]$cache_control, list(type = "ephemeral", ttl = "1h"))
  expect_equal(body$messages[[1L]]$content[[1L]]$cache_control,
               list(type = "ephemeral", ttl = "1h"))
  plan = default_plan(api, project = FALSE)
  expect_identical(plan$anchors, c("t0", "t1"))
  body = json_decode(anthropic_build(test_model(api), ctx_fixture(list(msg_user("hi")),
                                                                  cache_plan = plan),
                                     list())$body)
  expect_equal(body$system[[2L]]$cache_control, list(type = "ephemeral", ttl = "1h"))
})

test_that("without a project block the second breakpoint moves to the T1 system block", {
  plan = list(anchors = c("t0", "t1"), tail_ttl = "5m", key = "gptr:0123456789ab")
  body = json_decode(anthropic_build(test_model(api), ctx_fixture(list(msg_user("hi")),
                                                                  cache_plan = plan),
                                     list())$body)
  expect_equal(body$system[[2L]]$cache_control, list(type = "ephemeral", ttl = "1h"))
  # a cache plan that names neither T1 nor the project block marks only T0 and the tail
  plan = list(anchors = "t0", tail_ttl = "5m", key = "gptr:0123456789ab")
  req = anthropic_build(test_model(api), ctx_fixture(list(first_message()), cache_plan = plan),
                        list())
  expect_identical(lengths(regmatches(req$body, gregexpr("cache_control", req$body))), 2L)
  expect_null(json_decode(req$body)$messages[[1L]]$content[[1L]]$cache_control)
})

test_that("the frozen prefix stays byte-identical across turns and pieces are memoised", {
  model = test_model(api)
  memo = new.env(parent = emptyenv())
  b1 = anthropic_build(model, ctx_fixture(list(first_message())), list(memo = memo))$body
  b2 = anthropic_build(model, ctx_fixture(anthropic_turn2(model)), list(memo = memo))$body
  expect_true(startsWith(b2, substr(b1, 1L, nchar(b1) - 2L)))
  fresh = anthropic_build(model, ctx_fixture(anthropic_turn2(model)), list())$body
  expect_identical(b2, fresh)
  n = length(ls(memo))
  expect_gt(n, 0L)
  again = anthropic_build(model, ctx_fixture(anthropic_turn2(model)), list(memo = memo))$body
  expect_identical(again, b2)
  expect_identical(length(ls(memo)), n)
})

test_that("a PNG tool result is sent as a native image block (acceptance 3)", {
  model = test_model(api)
  msgs = anthropic_turn2(model)
  msgs[[3L]] = msg_tool_result("toolu_01A", "r", list(block_text("plot drawn"),
                                                      block_image(png_b64())))
  body = json_decode(anthropic_build(model, ctx_fixture(msgs), list())$body)
  result = body$messages[[3L]]$content[[1L]]
  expect_identical(result$type, "tool_result")
  expect_identical(result$tool_use_id, "toolu_01A")
  expect_identical(result$content[[2L]]$type, "image")
  expect_equal(result$content[[2L]]$source,
               list(type = "base64", media_type = "image/png", data = png_b64()))
  text_only = test_model(api, input = "text")
  body = json_decode(anthropic_build(text_only, ctx_fixture(msgs), list())$body)
  expect_identical(body$messages[[3L]]$content[[1L]]$content[[2L]]$type, "text")
})

test_that("signed and redacted thinking replay byte for byte only to the same model", {
  dir = sse_dir(api)
  model = adp_fixture_model(api, dir)
  msg = replay_case(api, anthropic_normaliser, "thinking_tools")$message
  ctx = ctx_fixture(list(first_message(), msg, msg_tool_result("toolu_01A", "r", "ok"),
                         msg_tool_result("toolu_01B", "read", "ok")))
  req = anthropic_build(model, ctx, list())
  parts = json_decode(req$body)$messages[[2L]]$content
  expect_identical(parts[[1L]]$type, "thinking")
  expect_identical(parts[[1L]]$signature, msg$content[[1L]]$signature)
  expect_identical(parts[[2L]], list(type = "redacted_thinking", data = msg$content[[2L]]$data))
  expect_true(grepl(msg$content[[2L]]$data, req$body, fixed = TRUE))
  expect_length(json_decode(req$body)$messages[[3L]]$content, 2L)
  other = json_decode(anthropic_build(test_model(api, id = "other-model"), ctx, list())$body)
  kinds = vapply(other$messages[[2L]]$content, function(p) p$type, "")
  expect_false(any(kinds %in% c("thinking", "redacted_thinking")))
  expect_identical(kinds[[1L]], "text")
})

test_that("adaptive models get adaptive thinking and effort; budget models an enabled budget", {
  body = json_decode(anthropic_build(test_model(api),
                                     ctx_fixture(list(msg_user("hi")),
                                                 params = list(thinking = "high")),
                                     list())$body)
  expect_equal(body$thinking, list(type = "adaptive", display = "omitted"))
  expect_identical(body$output_config$effort, "high")
  haiku = test_model(api, id = "claude-haiku-4-5", max_output = 64000,
                     capabilities = list(adaptive_thinking = FALSE, effort = FALSE))
  req = anthropic_build(haiku, ctx_fixture(list(msg_user("hi")),
                                           params = list(thinking = "medium", max_tokens = 4096L)),
                        list())
  body = json_decode(req$body)
  expect_equal(body$thinking, list(type = "enabled", budget_tokens = 8192L))
  expect_gt(body$max_tokens, 8192L)
  expect_null(body$output_config)
  expect_match(req$headers$`anthropic-beta`, "interleaved-thinking-2025-05-14", fixed = TRUE)
  haiku$max_output = 8192
  body = json_decode(anthropic_build(haiku, ctx_fixture(list(msg_user("hi")),
                                                        params = list(thinking = "high")),
                                     list())$body)
  expect_identical(body$max_tokens, 8192L)
  expect_lt(body$thinking$budget_tokens, body$max_tokens)
  # report 07 section 2.3: a temperature is never sent to a 5.x (adaptive) model
  cold = json_decode(anthropic_build(test_model(api),
                                     ctx_fixture(list(msg_user("hi")),
                                                 params = list(thinking = "off",
                                                               temperature = 0.2)),
                                     list())$body)
  expect_null(cold$thinking)
  expect_null(cold$temperature)
  warm = json_decode(anthropic_build(haiku, ctx_fixture(list(msg_user("hi")),
                                                        params = list(temperature = 0.2)),
                                     list())$body)
  expect_null(warm$thinking)
  expect_identical(warm$temperature, 0.2)
})

test_that("returns = uses output_config.format and keeps the tools (IC-71, INFRA-25)", {
  schema = list(type = "object", required = I("rows"),
                properties = list(rows = list(type = "integer")))
  req = anthropic_build(test_model(api), ctx_fixture(list(msg_user("rows?")),
                                                     params = list(returns = schema)), list())
  body = json_decode(req$body)
  expect_identical(body$output_config$format$type, "json_schema")
  expect_identical(body$output_config$format$schema$required, list("rows"))
  expect_identical(vapply(body$tools, function(t) t$name, ""), c("read", "r"))
  expect_null(body$tool_choice)
  plain = test_model(api, structured_output = FALSE)
  body = json_decode(anthropic_build(plain, ctx_fixture(list(msg_user("rows?")),
                                                        params = list(returns = schema)),
                                     list())$body)
  expect_null(body$output_config$format)
  last = body$messages[[length(body$messages)]]
  expect_identical(last$role, "system")
  expect_match(last$content[[1L]]$text, "JSON Schema", fixed = TRUE)
})

test_that("a forced tool_choice is never sent while forced_tool_choice is FALSE (IC-71)", {
  forced = list(tool_choice = list(type = "tool", name = "read"))
  no = test_model(api, reasoning = FALSE, capabilities = list(forced_tool_choice = FALSE))
  body = json_decode(anthropic_build(no, ctx_fixture(list(msg_user("x")), params = forced),
                                     list())$body)
  expect_null(body$tool_choice)
  silent = test_model(api, reasoning = FALSE, capabilities = list())
  body = json_decode(anthropic_build(silent, ctx_fixture(list(msg_user("x")), params = forced),
                                     list())$body)
  expect_null(body$tool_choice)
  yes = test_model(api, reasoning = FALSE, capabilities = list(forced_tool_choice = TRUE))
  body = json_decode(anthropic_build(yes, ctx_fixture(list(msg_user("x")), params = forced),
                                     list())$body)
  expect_equal(body$tool_choice, list(type = "tool", name = "read"))
  body = json_decode(anthropic_build(yes, ctx_fixture(list(msg_user("x")),
                                                      params = list(tool_choice = "none")),
                                     list())$body)
  expect_equal(body$tool_choice, list(type = "none"))
})

test_that("operator messages are system messages only where the placement rule allows", {
  model = test_model(api)
  relay = msg_operator("steer_relay",
                       "The user sent this message while you were working: use TPM")
  body = json_decode(anthropic_build(model, ctx_fixture(c(anthropic_turn2(model), list(relay))),
                                     list())$body)
  expect_identical(body$messages[[length(body$messages)]]$role, "system")
  old = test_model(api, capabilities = list(mid_system = FALSE))
  body = json_decode(anthropic_build(old, ctx_fixture(c(anthropic_turn2(model), list(relay))),
                                     list())$body)
  expect_identical(body$messages[[length(body$messages)]]$role, "user")
  before_user = c(anthropic_turn2(model), list(relay, msg_user("and then?")))
  body = json_decode(anthropic_build(model, ctx_fixture(before_user), list())$body)
  roles = vapply(body$messages, function(m) m$role, "")
  expect_false("system" %in% roles)
  add = msg_operator("tool_change", "New tool: lint.",
                     tool_add = list(list(name = "lint", description = "Lint a file.",
                                          input_schema = list(type = "object"))))
  req = anthropic_build(model, ctx_fixture(c(anthropic_turn2(model), list(add))), list())
  parts = json_decode(req$body)$messages[[4L]]$content
  expect_identical(parts[[2L]]$type, "tool_addition")
  expect_identical(parts[[2L]]$tool$definition$name, "lint")
  expect_match(req$headers$`anthropic-beta`, "inline-tools-2026-09-15", fixed = TRUE)
})

test_that("a run of operator messages is one system message, never two in a row (07 2.3)", {
  model = test_model(api)
  mode = msg_operator("mode", "Mode changed to auto.")
  relay = msg_operator("steer_relay",
                       "The user sent this message while you were working: use TPM")
  body = json_decode(anthropic_build(model, ctx_fixture(c(anthropic_turn2(model),
                                                          list(mode, relay))),
                                     list())$body)
  expect_identical(vapply(body$messages, function(m) m$role, ""),
                   c("user", "assistant", "user", "system"))
  expect_identical(vapply(body$messages[[4L]]$content, function(p) p$text, ""),
                   c("Mode changed to auto.",
                     "The user sent this message while you were working: use TPM"))
  # a returns instruction closes the request: the trailing run is user text, the instruction
  # the one system message after it
  plain = test_model(api, structured_output = FALSE)
  ctx = ctx_fixture(c(anthropic_turn2(model), list(relay)),
                    params = list(returns = count_schema()))
  roles = vapply(json_decode(anthropic_build(plain, ctx, list())$body)$messages,
                 function(m) m$role, "")
  expect_identical(roles, c("user", "assistant", "user", "user", "system"))
})

test_that("credentials stay handles: x-api-key, or Bearer with the oauth beta", {
  key = fake_handle("ANTHROPIC_API_KEY")
  req = anthropic_build(test_model(api), ctx_fixture(list(msg_user("x"))),
                        list(credential = key, base_url = "https://api.anthropic.com"))
  expect_identical(req$url, "https://api.anthropic.com/v1/messages")
  expect_identical(req$method, "POST")
  expect_identical(req$headers$`x-api-key`, key)
  expect_identical(req$headers$`anthropic-version`, "2023-06-01")
  expect_identical(req$stream, "sse")
  tok = fake_handle("ANTHROPIC_AUTH_TOKEN")
  req = anthropic_build(test_model(api), ctx_fixture(list(msg_user("x"))), list(credential = tok))
  expect_identical(req$headers$authorization, list("Bearer ", tok))
  expect_null(req$headers$`x-api-key`)
  expect_match(req$headers$`anthropic-beta`, "oauth-2025-04-20", fixed = TRUE)
  expect_false(grepl("abc123", req$body, fixed = TRUE))
})

test_that("declared request params reach the body; others do not (IC-69)", {
  ctx = ctx_fixture(list(msg_user("x")), params = list(service_tier = "auto", user = "u1"))
  body = json_decode(anthropic_build(test_model(api), ctx, list())$body)
  expect_identical(body$service_tier, "auto")
  expect_null(body$user)
})

test_that("builtin:anthropic registers the adapter with its capabilities", {
  a = adapter_get(api)
  expect_s3_class(a, "gptr_adapter")
  expect_identical(a$transport, "http_sse")
  expect_false(a$capabilities$forced_tool_choice)
  expect_identical(a$capabilities$request_params, c("service_tier", "metadata"))
  expect_identical(a$capabilities$max_tool_name, 128L)
})

test_that("provider_stream() puts the returns schema on the wire (INFRA-25)", {
  local_scripted_provider(api)
  wire = local_scripted_wire(list(anthropic_sse_text("{\"n\":32}")))
  out = new.env(parent = emptyenv())
  out$msg = NULL
  ctx = ctx_fixture(list(msg_user("How many rows?")), params = list(returns = count_schema()))
  provider_stream(model_resolve("scripted/scripted-1"), ctx, list(), emit = function(ev) NULL,
                  done = function(msg) out$msg = msg)
  reactor_pump(until = function() !is.null(out$msg), timeout = 10)
  body = json_decode(wire$requests[[1L]]$body)
  expect_identical(body$output_config$format$type, "json_schema")
  expect_identical(body$output_config$format$schema$required, list("n"))
  expect_identical(msg_text(out$msg), "{\"n\":32}")
})

test_that("returns = through the run loop: a typed value and the tool calls kept (INFRA-25)", {
  local_gptr_options(unsafe_no_permissions = TRUE)
  local_scripted_provider(api)
  local_count_tool()
  wire = local_scripted_wire(list(anthropic_sse_tool("toolu_01", "count", "{}"),
                                  anthropic_sse_text("{\"n\":32}")))
  s = session_new("scripted/scripted-1", "auto", home = new.env())
  session_run(s, msg_user("How many rows?"), list(returns = count_schema()))
  expect_identical(s$value$n, 32L)
  expect_identical(vapply(s$messages, function(m) m$role, ""),
                   c("user", "assistant", "tool_result", "assistant"))
  expect_length(wire$requests, 2L)
  expect_match(wire$requests[[1L]]$url, "/v1/messages$")
  # the run's returns schema reaches the wire through P07's request context (IC-71)
  first = json_decode(wire$requests[[1L]]$body)
  expect_identical(first$output_config$format$type, "json_schema")
  expect_identical(first$output_config$format$schema$required, list("n"))
  expect_true("count" %in% vapply(first$tools, function(t) t$name, ""))
  second = json_decode(wire$requests[[2L]]$body)
  kinds = unlist(lapply(second$messages, function(m) vapply(m$content, function(b) b$type, "")))
  expect_true(all(c("tool_use", "tool_result") %in% kinds))
})

test_that("end to end on the mock server: streaming, retry and abort (skip on CRAN)", {
  skip_on_cran()
  srv = local_mock_server("stream", n = 3L, interval = 0.02)
  r = mock_stream(srv)
  expect_identical(r$types, c("start", "text_start", rep("text_delta", 3L), "text_end", "done"))
  expect_identical(msg_text(r$message), "tok01 tok02 tok03 ")
  expect_identical(r$message$usage$input, 100)
  over = local_mock_server("overload", attempts = 1L)
  r = mock_stream(over)
  expect_identical(r$message$stop_reason, "stop")
  expect_identical(nrow(over$log()), 2L)
  expect_identical(sum(r$types == "start"), 1L)
  slow = local_mock_server("stream", n = 12L, interval = 0.2)
  r = mock_stream(slow, abort_after = 2L)
  expect_identical(r$message$stop_reason, "aborted")
  expect_identical(msg_text(r$message), "tok01 tok02 ")
  expect_identical(r$types[[length(r$types)]], "error")
  tools = local_mock_server("parallel_tools")
  r = mock_stream(tools)
  expect_identical(r$message$stop_reason, "tool_use")
  expect_identical(vapply(r$message$content, function(b) b$name, ""), c("read", "r"))
  expect_identical(r$message$content[[2L]]$arguments, list(code = "1 + 1"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-anthropic")'`
Expected: `[ FAIL 20 | WARN 0 | SKIP 0 | PASS 99 ]`, with errors such as ``could not find function "anthropic_build"`` and `No adapter is registered for the api anthropic-messages.`

- [ ] **Step 3: Write the implementation**

Append to `R/provider-anthropic.R`:

```r
# ---- shared request helpers -------------------------------------------------------------------

#' A model capability: the record's `capabilities` entry, then a top-level field, then `default`
#' @noRd
adp_model_cap = function(model, name, default = FALSE) {
  v = model$capabilities[[name]] %||% model[[name]]
  if (is.null(v) || length(v) != 1L || is.na(v)) default else v
}

#' Was msg produced by exactly this model through this api? (opaque data replays only then)
#' @noRd
adp_same_model = function(msg, model) {
  identical(msg$api, model$api) && identical(msg$provider, model$provider) &&
    identical(msg$model, model$id)
}

#' Does the model take image input? (images are otherwise replaced by a one-line note)
#' @noRd
adp_images_ok = function(model) "image" %in% unlist(model$input %||% "text")

#' The note sent in place of an image to a model without image input
#' @noRd
adp_image_note = function() "(image omitted: this model does not accept images)"

#' A header value that holds a secret handle; only http-request.R (P04) materialises it
#' @noRd
adp_header_secret = function(handle, prefix = "") {
  if (is.null(handle)) return(NULL)
  if (!nzchar(prefix)) return(handle)
  list(prefix, handle)
}

#' Join a base URL and a path with exactly one slash
#' @noRd
adp_url = function(base, path) paste0(sub("/+$", "", base), "/", sub("^/+", "", path))

#' The non-secret headers of the model's provider record (for example OpenRouter attribution)
#' @noRd
adp_provider_headers = function(model) {
  id = model$provider %||% ""
  if (!is.character(id) || length(id) != 1L || !nzchar(id)) return(list())
  rec = provider_get(id)
  h = rec$headers
  if (is.null(h) || !length(h)) list() else as.list(h)
}

#' The instruction sent with `returns =` where no native structured output is used (IC-71)
#' @noRd
adp_returns_instruction = function(schema) {
  paste0("When your work is complete, reply with only a JSON value that matches this JSON ",
         "Schema, with no other text and no code fence: ", json_encode(schema))
}

#' Serialise once per session: the value stored in opts$memo under `key`, computed on a miss
#' @noRd
adp_memo = function(opts, key, fun) {
  memo = opts$memo
  if (!is.environment(memo)) return(fun())
  hit = get0(key, envir = memo, inherits = FALSE)
  if (!is.null(hit)) return(hit)
  val = fun()
  assign(key, val, envir = memo)
  val
}

#' The memo key of a message: projected messages carry no entry id, so a hash of the fields
#' that reach the wire (timestamps, usage and details are left out so a rebuilt copy hits)
#' @noRd
adp_msg_key = function(msg) {
  keep = c("role", "content", "api", "provider", "model", "tool_call_id", "tool_name",
           "is_error", "kind", "tool_add")
  hash_xxh128(msg[intersect(keep, names(msg))])
}

#' Tool-call ids restricted to [A-Za-z0-9_-] and a maximum length
#' @noRd
adp_sanitize_id = function(id, max = 64L) substr(gsub("[^A-Za-z0-9_-]", "_", id), 1L, max)

#' The frozen tool array converted once per session for an api; NULL when there are no tools
#' @noRd
adp_tools_json = function(opts, api, tools_json, convert) {
  if (is.null(tools_json)) return(NULL)
  text = as.character(tools_json)
  key = paste(api, "tools", hash_xxh128(text), sep = "|")
  out = adp_memo(opts, key, function() {
    tools = json_decode(text)
    if (!length(tools)) "" else json_encode(convert(tools))
  })
  if (nzchar(out)) out else NULL
}

#' Does any projected message hold a tool call or a tool result?
#' @noRd
adp_has_tool_calls = function(msgs) {
  for (m in msgs) {
    if (identical(m$role, "tool_result")) return(TRUE)
    if (identical(m$role, "assistant")) {
      for (b in m$content) if (identical(b$type, "tool_call")) return(TRUE)
    }
  }
  FALSE
}

#' Index of the first user message that holds an anchored context block (the BP2 anchor)
#' @noRd
adp_anchor_index = function(msgs) {
  for (k in seq_along(msgs)) {
    m = msgs[[k]]
    if (!identical(m$role, "user")) next
    for (b in m$content) if (identical(b$type, "context") && isTRUE(b$anchor)) return(k)
  }
  0L
}

#' The text of an operator message
#' @noRd
adp_operator_text = function(m) {
  paste(vapply(m$content, function(b) b$text %||% "", ""), collapse = "\n")
}

#' The effort for a thinking level: `minimal` maps to `low`, `off` and NULL to none
#' @noRd
adp_level_effort = function(level) {
  if (is.null(level) || identical(level, "off")) return(NULL)
  if (identical(level, "minimal")) "low" else level
}

#' Thinking budget in tokens for budget-based models (report 03 section 5.5 defaults)
#' @noRd
adp_budget = function(level) {
  switch(level, minimal = 1024L, low = 2048L, medium = 8192L, 16384L)
}

#' Assemble a JSON body: the head fields, the extra members, then the growing array last
#' @noRd
adp_body = function(head, extra, key, elements) {
  h = json_encode(head)
  inner = substr(h, 2L, nchar(h) - 1L)
  parts = c(if (nzchar(inner)) inner, extra,
            paste0("\"", key, "\":[", paste(elements, collapse = ","), "]"))
  paste0("{", paste(parts, collapse = ","), "}")
}

#' The cache plan of the request context (04 section 8.1), or the Anthropic default
#' @noRd
adp_cache_plan = function(context) {
  context$cache_plan %||% list(anchors = c("t0", "project"), tail_ttl = "5m", key = NULL)
}

#' Is a tool_choice a forced choice (a list naming a tool, or `any`)?
#' @noRd
adp_forced = function(tc) {
  is.list(tc) && !((tc$type %||% "") %in% c("auto", "none"))
}

#' May a forced tool_choice be sent? Model capability first, then the adapter's (IC-71)
#' @noRd
adp_forced_ok = function(model, caps) {
  isTRUE(adp_model_cap(model, "forced_tool_choice", isTRUE(caps$forced_tool_choice)))
}

# ---- anthropic-messages: request body ---------------------------------------------------------

#' Adapter capabilities of anthropic-messages (04 section 8.1; IC-69, IC-71)
#' @noRd
anthropic_caps = function() {
  list(images_in_results = TRUE, tool_addition = TRUE, structured_output = TRUE,
       reasoning_replay = TRUE, parallel_tools = TRUE, forced_tool_choice = FALSE,
       request_params = c("service_tier", "metadata"), operator_role = "system",
       cache = "anthropic", max_tool_name = 128L, tool_shape = "anthropic")
}

#' An Anthropic image content block (base64 source), or a text note for a text-only model
#' @noRd
anthropic_image = function(b, images) {
  if (!images) return(list(type = "text", text = adp_image_note()))
  list(type = "image", source = list(type = "base64", media_type = b$mime, data = b$data))
}

#' A user message; the anchored context block carries the 1 h BP2 marker
#' @noRd
anthropic_user = function(m, mark_anchor, images) {
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    if (type == "text" && nzchar(trimws(b$text))) {
      parts[[length(parts) + 1L]] = list(type = "text", text = b$text)
    } else if (type == "context") {
      p = list(type = "text", text = b$text)
      if (mark_anchor && isTRUE(b$anchor)) p$cache_control = list(type = "ephemeral", ttl = "1h")
      parts[[length(parts) + 1L]] = p
    } else if (type == "image") {
      parts[[length(parts) + 1L]] = anthropic_image(b, images)
    }
  }
  if (!length(parts)) return(NULL)
  list(role = "user", content = parts)
}

#' An assistant message; signed thinking, redacted thinking and opaque blocks are replayed
#' byte for byte only to the model that produced them (INFRA-07)
#' @noRd
anthropic_assistant = function(m, model) {
  same = adp_same_model(m, model)
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    p = NULL
    if (type == "text") {
      if (nzchar(trimws(b$text))) p = list(type = "text", text = b$text)
    } else if (type == "thinking") {
      if (isTRUE(b$redacted)) {
        if (same && !is.null(b$data)) p = list(type = "redacted_thinking", data = b$data)
      } else if (same && nzchar(b$signature %||% "")) {
        p = list(type = "thinking", thinking = b$thinking, signature = b$signature)
      } else if (nzchar(trimws(b$thinking))) {
        p = list(type = "text", text = b$thinking)
      }
    } else if (type == "tool_call") {
      args = if (length(b$arguments)) b$arguments else json_obj()
      p = list(type = "tool_use", id = adp_sanitize_id(b$id), name = b$name, input = args)
    } else if (type == "opaque") {
      if (same) p = json_verbatim(b$json)
    }
    if (!is.null(p)) parts[[length(parts) + 1L]] = p
  }
  if (!length(parts)) return(NULL)
  list(role = "assistant", content = parts)
}

#' One tool_result block: text first, images as native image blocks (acceptance 3);
#' whitespace-only text blocks are left out, the rule anthropic_user() and anthropic_assistant()
#' apply (the Messages API refuses text blocks without non-whitespace text)
#' @noRd
anthropic_tool_result = function(r, images) {
  content = list()
  has_text = FALSE
  for (b in r$content) {
    if (identical(b$type, "text") && nzchar(trimws(b$text))) {
      content[[length(content) + 1L]] = list(type = "text", text = b$text)
      has_text = TRUE
    } else if (identical(b$type, "image")) {
      content[[length(content) + 1L]] = anthropic_image(b, images)
    }
  }
  if (!has_text && length(content)) {
    content = c(list(list(type = "text", text = "(see attached image)")), content)
  }
  out = list(type = "tool_result", tool_use_id = adp_sanitize_id(r$tool_call_id))
  if (length(content)) out$content = content
  if (isTRUE(r$is_error)) out$is_error = TRUE
  out
}

#' A run of operator messages as ONE message: a mid-conversation system message (with
#' tool_addition blocks when the model takes them) where the placement rule allows it, else user
#' text (G4 section 2.3). Report 07 section 2.3: a system message must follow a user message and
#' be last or followed by an assistant turn, so a run is never split into consecutive system
#' messages
#' @noRd
anthropic_operator = function(group, as_system, with_tools) {
  parts = list()
  for (m in group) {
    text = adp_operator_text(m)
    if (nzchar(text)) parts[[length(parts) + 1L]] = list(type = "text", text = text)
    if (!with_tools) next
    for (t in m$tool_add %||% list()) {
      def = list(name = t$name, description = t$description, input_schema = t$input_schema)
      parts[[length(parts) + 1L]] = list(type = "tool_addition",
                                         tool = list(type = "tool_definition", definition = def))
    }
  }
  if (!length(parts)) return(NULL)
  list(role = if (as_system) "system" else "user", content = parts)
}

#' The messages array elements (JSON text), each serialised once per session through opts$memo.
#' Consecutive tool results become one user message; a run of operator messages becomes one
#' message, a system message only when it follows a user turn and precedes an assistant turn or
#' the end (`tail = TRUE`: a `returns` instruction follows the last element, so a trailing run is
#' user text and the instruction can be the closing system message); the anchored project block
#' carries BP2 only when the cache plan names `project`
#' @noRd
anthropic_elements = function(model, msgs, opts, anchors = "project", tail = FALSE) {
  out = character()
  betas = character()
  mid = isTRUE(adp_model_cap(model, "mid_system", FALSE))
  add_tools = isTRUE(adp_model_cap(model, "tool_addition", TRUE))
  images = adp_images_ok(model)
  anchor_at = if ("project" %in% anchors) adp_anchor_index(msgs) else 0L
  prev = "none"
  n = length(msgs)
  i = 1L
  while (i <= n) {
    m = msgs[[i]]
    role = m$role %||% ""
    if (role %in% c("tool_result", "operator")) {
      j = i
      while (j <= n && identical(msgs[[j]]$role, role)) j = j + 1L
      group = msgs[i:(j - 1L)]
      if (role == "tool_result") {
        key = paste(c("anthropic", "results", images, vapply(group, adp_msg_key, "")),
                    collapse = "|")
        el = adp_memo(opts, key, function() {
          json_encode(list(role = "user",
                           content = lapply(group, anthropic_tool_result, images = images)))
        })
        out = c(out, el)
        prev = "user"
      } else {
        nxt = if (j <= n) msgs[[j]]$role %||% "" else if (tail) "user" else "end"
        as_system = mid && identical(prev, "user") && nxt %in% c("assistant", "end")
        with_tools = as_system && add_tools &&
          any(vapply(group, function(op) length(op$tool_add) > 0L, logical(1)))
        if (with_tools) betas = c(betas, "inline-tools-2026-09-15")
        key = paste(c("anthropic", "operator", vapply(group, adp_msg_key, ""), as_system,
                      with_tools), collapse = "|")
        el = adp_memo(opts, key, function() {
          x = anthropic_operator(group, as_system, with_tools)
          if (is.null(x)) "" else json_encode(x)
        })
        if (nzchar(el)) {
          out = c(out, el)
          prev = if (as_system) "system" else "user"
        }
      }
      i = j
      next
    }
    same = adp_same_model(m, model)
    mark = identical(i, anchor_at)
    key = paste("anthropic", role, adp_msg_key(m), same, mark, images, sep = "|")
    el = adp_memo(opts, key, function() {
      x = NULL
      if (role == "user") x = anthropic_user(m, mark, images)
      if (role == "assistant") x = anthropic_assistant(m, model)
      if (is.null(x)) "" else json_encode(x)
    })
    if (nzchar(el)) {
      out = c(out, el)
      prev = role
    }
    i = i + 1L
  }
  list(elements = out, betas = unique(betas), prev = prev, mid = mid)
}

#' Thinking, effort and budget of a request: adaptive models get adaptive thinking and an
#' effort, budget models `enabled` with a budget and the interleaved beta (07 section 2.6)
#' @noRd
anthropic_thinking = function(model, params) {
  out = list(thinking = NULL, effort = NULL, budget = NULL, betas = character())
  if (!isTRUE(model$reasoning)) return(out)
  level = params$thinking
  if (isTRUE(adp_model_cap(model, "adaptive_thinking", FALSE))) {
    if (!identical(level, "off")) {
      out$thinking = list(type = "adaptive",
                          display = if (gptr_has_human()) "summarized" else "omitted")
    }
    if (isTRUE(adp_model_cap(model, "effort", TRUE))) {
      out$effort = params$effort %||% adp_level_effort(level)
    }
  } else if (!is.null(level) && !identical(level, "off")) {
    out$budget = adp_budget(level)
    out$thinking = list(type = "enabled", budget_tokens = out$budget)
    out$betas = "interleaved-thinking-2025-05-14"
  }
  out
}

#' The tool_choice field of a request, or NULL for the default `auto` (IC-71)
#' @noRd
anthropic_tool_choice = function(tc, model, thinking, returns) {
  if (identical(tc, "none")) return(list(type = "none"))
  if (!adp_forced(tc) || !adp_forced_ok(model, anthropic_caps())) return(NULL)
  if (!is.null(thinking) || !is.null(returns)) return(NULL)
  if (identical(tc$type, "any")) return(list(type = "any"))
  list(type = "tool", name = tc$name)
}

#' build() of the anthropic-messages adapter (04 section 8.1): the request spec
#'
#' Body key order per G4 section 3.7: model, max_tokens, stream, cache_control (the automatic
#' tail breakpoint), thinking, output_config, tool_choice, declared request params, tools,
#' system (T0 with the 1 h BP1, T1), messages (the project block with the 1 h BP2).
#' @noRd
anthropic_build = function(model, context, opts) {
  params = context$params %||% list()
  plan = adp_cache_plan(context)
  anchors = plan$anchors %||% character()
  msgs = context$messages %||% list()
  cc1h = list(type = "ephemeral", ttl = "1h")
  native_returns = !is.null(params$returns) && isTRUE(model$structured_output)
  tail = !is.null(params$returns) && !native_returns
  rendered = anthropic_elements(model, msgs, opts, anchors, tail)
  th = anthropic_thinking(model, params)
  betas = c(rendered$betas, th$betas)

  max_tokens = params$max_tokens %||% model$max_output %||% 64000L
  if (is.null(max_tokens) || is.na(max_tokens)) max_tokens = 64000L
  if (!is.null(th$budget)) max_tokens = max(max_tokens, th$budget + 1024L)
  cap = model$max_output
  if (!is.null(cap) && !is.na(cap)) max_tokens = min(max_tokens, cap)
  if (!is.null(th$budget)) {
    budget = min(th$budget, max(1024L, max_tokens - 1024L))
    th$thinking = list(type = "enabled", budget_tokens = as.integer(budget))
  }

  head = list(model = model$id, max_tokens = as.integer(max_tokens), stream = TRUE)
  head$cache_control = if (identical(plan$tail_ttl, "1h")) cc1h else list(type = "ephemeral")
  if (!is.null(th$thinking)) head$thinking = th$thinking
  oc = list()
  if (!is.null(th$effort)) oc$effort = th$effort
  if (native_returns) oc$format = list(type = "json_schema", schema = params$returns)
  if (length(oc)) head$output_config = oc
  tc = anthropic_tool_choice(params$tool_choice, model, th$thinking, params$returns)
  if (!is.null(tc)) head$tool_choice = tc
  # report 07 section 2.3: a non-default temperature is a 400 on every 5.x (adaptive) model
  adaptive = isTRUE(adp_model_cap(model, "adaptive_thinking", FALSE))
  if (!is.null(params$temperature) && is.null(th$thinking) && !adaptive) {
    head$temperature = params$temperature
  }
  for (f in anthropic_caps()$request_params) if (!is.null(params[[f]])) head[[f]] = params[[f]]

  extra = character()
  tools = context$tools_json
  if (!is.null(tools) && !identical(trimws(as.character(tools)), "[]")) {
    extra = c(extra, paste0("\"tools\":", as.character(tools)))
  }
  sys = list()
  t0 = context$system$t0 %||% ""
  t1 = context$system$t1 %||% ""
  if (nzchar(t0)) {
    s = list(type = "text", text = t0)
    if ("t0" %in% anchors) s$cache_control = cc1h
    sys[[length(sys) + 1L]] = s
  }
  if (nzchar(t1)) {
    s = list(type = "text", text = t1)
    no_anchor = "project" %in% anchors && adp_anchor_index(msgs) == 0L
    if ("t1" %in% anchors || no_anchor) s$cache_control = cc1h
    sys[[length(sys) + 1L]] = s
  }
  if (length(sys)) {
    sys_json = adp_memo(opts, paste("anthropic", "system", hash_xxh128(sys), sep = "|"),
                        function() json_encode(sys))
    extra = c(extra, paste0("\"system\":", sys_json))
  }

  elements = rendered$elements
  if (tail) {
    as_system = rendered$mid && identical(rendered$prev, "user")
    instr = list(role = if (as_system) "system" else "user",
                 content = list(list(type = "text",
                                     text = adp_returns_instruction(params$returns))))
    elements = c(elements, json_encode(instr))
  }

  headers = list(`content-type` = "application/json", accept = "text/event-stream",
                 `anthropic-version` = "2023-06-01")
  cred = opts$credential
  if (!is.null(cred)) {
    if (identical(cred$name, "ANTHROPIC_AUTH_TOKEN")) {
      headers$authorization = adp_header_secret(cred, "Bearer ")
      betas = c(betas, "oauth-2025-04-20")
    } else {
      headers$`x-api-key` = adp_header_secret(cred)
    }
  }
  if (length(betas)) headers$`anthropic-beta` = paste(unique(betas), collapse = ",")
  headers = c(headers, adp_provider_headers(model))

  list(url = adp_url(opts$base_url %||% "https://api.anthropic.com", "v1/messages"),
       method = "POST", headers = headers,
       body = adp_body(head, extra, "messages", elements), stream = "sse")
}

#' builtin:anthropic: registers the anthropic-messages adapter (04 sections 7.12, 10.3)
#' @noRd
builtin_anthropic = function(gptr) {
  gptr$register(gptr_adapter("anthropic-messages", transport = "http_sse",
                             build = anthropic_build, parse = anthropic_normaliser,
                             capabilities = anthropic_caps()))
  invisible(NULL)
}

on_load(ext_declare_builtin("anthropic", builtin_anthropic))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-anthropic")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 204 ]` (the mock-server test starts P01's base-R server with `rscript_path()`; it skips on CRAN).

- [ ] **Step 5: Commit**

```bash
git add R/provider-anthropic.R tests/testthat/test-provider-anthropic.R tests/testthat/fixtures/sse/replay_helpers.R
git commit -m "feat(provider): build anthropic-messages request bodies and register builtin:anthropic"
```

---

### Task 3: `check_adapter()` and the `check.adapter` service

**Files:**
- Modify: `R/provider-anthropic.R` (append)
- Test: `tests/testthat/test-provider-anthropic.R` (append)

**Interfaces:**
- Consumes: `ext_service_set(name, fun, provided_by, builtin = NULL)`, `on_load(expr)`, `canonical_json(x)`, `msg_to_json(msg)`, `msg_from_json(x)`, `msg_user()`, `msg_tool_result()`, `json_verbatim()`, `read_utf8()` (P01); tests use `gptr_check(x, error = FALSE, tokens = FALSE)` (P02, which calls the service as `adapter_check(spec)` and turns its rows into `gptr_check` rows), `gptr_adapter(api, transport = c(...), build = NULL, parse = NULL, stream = NULL, classify = NULL, capabilities = list())` (P02; a classifier adapter in the IC-35 shape), `ext_service_has(name)`, `write_utf8(path, text, eol = "\n", bom = FALSE, final_newline = TRUE)` (P01).
- Produces: `check_adapter(adapter, fixtures = NULL)` (04 section 7.12) -> a `gptr_check` data frame (columns `target`, `check`, `ok`, `message`; 04 section 5.11) with target `adapter:<api>`, registered as the service `check.adapter` (`function(adapter, fixtures = NULL) <gptr_check>`, 04 section 7.0), owned by `builtin:anthropic` (IC-34). Check names: `adapter.tool_choice`; `adapter.fixtures` (only when none are found); per case `adapter.<case>.no_condition`, `.event_order`, `.golden_events`, `.golden_message`, `.chunk_invariance` and, for cases that end in `done`, `.roundtrip`; `adapter.replay` for `inprocess` adapters and for classifier adapters without a top-level `parse` (P13's `typesafe-system-one` is `http_json` with only `classify`; nothing to replay, so `gptr_check()` on it does not fail for want of stream fixtures).

What it checks (05 P12 acceptance 2 and review amendments, 04 section 6.7 `gptr_check()`): no R condition escapes the normaliser; exactly one `start` first and one terminal event last; golden events and final message; identical events when the bytes arrive whole, one byte at a time and in three chunkings of 1-17 bytes derived from sha256 bits (RNG-free, IC-61); byte-identical re-serialisation (the final message, and its JSON round trip through the session-file form, build the same body with and without the memo, and every signature, redacted payload, thought signature and opaque item is on the wire verbatim); and "a list `tool_choice` sent while the model capability `forced_tool_choice` is `FALSE` fails". Fixtures come from `fixtures`, else `fixtures/sse/<api>` under the working directory (testthat runs in `tests/testthat`), else `tests/testthat/fixtures/sse/<api>`; a `model.json` in the fixture directory overrides fields of the fixture model record.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-provider-anthropic.R`:

```r
# ---- conformance: check_adapter() and the check.adapter service (Task 3) -----------------------

test_that("check_adapter() passes for anthropic-messages on its fixtures (acceptance 2)", {
  res = check_adapter(adapter_get(api), fixtures = sse_dir(api))
  expect_s3_class(res, "gptr_check")
  expect_identical(names(res), c("target", "check", "ok", "message"))
  expect_true(all(res$target == "adapter:anthropic-messages"))
  expect_true(all(res$ok), label = paste(res$check[!res$ok], collapse = "; "))
  expect_true("adapter.tool_choice" %in% res$check)
  for (case in c("text", "thinking_tools", "error_midstream", "truncated", "refusal",
                 "server_tool")) {
    expect_true(paste0("adapter.", case, ".chunk_invariance") %in% res$check)
  }
  expect_true("adapter.thinking_tools.roundtrip" %in% res$check)
  expect_false("adapter.truncated.roundtrip" %in% res$check)
})

test_that("check_adapter() fails a normaliser that throws and a forced tool_choice", {
  good = adapter_get(api)
  broken = good
  broken$parse = function(model, opts) {
    list(push = function(ev) stop("boom"), finish = function() NULL,
         fail = function(cnd) NULL, message = function() NULL)
  }
  res = check_adapter(broken, fixtures = sse_dir(api))
  expect_identical(sum(grepl("\\.no_condition$", res$check)), 6L)
  expect_false(any(res$ok[grepl("\\.no_condition$", res$check)]))
  pushy = good
  pushy$build = function(model, context, opts) {
    req = anthropic_build(model, context, opts)
    req$body = sub("\"stream\":true",
                   "\"stream\":true,\"tool_choice\":{\"type\":\"tool\",\"name\":\"read\"}",
                   req$body, fixed = TRUE)
    req
  }
  res = check_adapter(pushy, fixtures = sse_dir(api))
  expect_false(res$ok[res$check == "adapter.tool_choice"])
})

test_that("check_adapter() fails when events differ from the golden file", {
  dir = withr::local_tempdir()
  file.copy(list.files(sse_dir(api), full.names = TRUE), dir)
  path = file.path(dir, "text.events.json")
  golden = json_decode(read_utf8(path)$text)
  golden[[3L]]$delta = "Goodbye, "
  write_utf8(path, json_encode(golden, pretty = TRUE))
  res = check_adapter(adapter_get(api), fixtures = dir)
  expect_false(res$ok[res$check == "adapter.text.golden_events"])
  expect_true(res$ok[res$check == "adapter.refusal.golden_events"])
})

test_that("check_adapter() reports missing fixtures and skips inprocess and classifier adapters", {
  res = check_adapter(adapter_get(api), fixtures = withr::local_tempdir())
  expect_false(res$ok[res$check == "adapter.fixtures"])
  fake = check_adapter(adapter_get("fake"))
  expect_identical(fake$check, "adapter.replay")
  expect_true(fake$ok)
  # a classifier adapter (P13's typesafe-system-one shape): http_json with only `classify`
  cls = gptr_adapter("cls-fixture", transport = "http_json",
                     classify = list(build = function(model, state, questions, opts) NULL,
                                     parse = function(model, status, headers, body) NULL))
  res = check_adapter(cls)
  expect_identical(res$check, "adapter.replay")
  expect_true(res$ok)
  expect_true(all(gptr_check(cls)$ok))
})

test_that("the check.adapter service makes gptr_check() replay the fixtures (acceptance 2)", {
  expect_true(ext_service_has("check.adapter"))
  a = adapter_get(api)
  res = gptr_check(a)
  expect_true(all(c("spec.class", "spec.fields", "adapter.text.golden_events") %in% res$check))
  expect_true(all(res$ok), label = paste(res$check[!res$ok], collapse = "; "))
})
```

- [ ] **Step 2: Run it to verify it fails**

First confirm the P02 precondition of the Global Constraints:

```bash
grep -n "^check_adapter = function" R/*.R
```

Expected: no output. If it prints `R/ext-check.R:...: check_adapter = function(spec, target, adapter_check) {`, stop: P02's private helper still has the name 04 section 7.12 gives to P12, and this task's function would replace it (`gptr_check()` on any adapter would then fail with `unused argument (adapter_check)`); ask the maintainer to rename P02's helper (for example `check_adapter_rows()`, with its one call in `check_spec()`) before continuing.

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-anthropic")'`
Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 205 ]`, with errors such as ``could not find function "check_adapter"``.

- [ ] **Step 3: Write the implementation**

Append to `R/provider-anthropic.R`:

```r
# ---- conformance: check_adapter() (the check.adapter service) ---------------------------------

#' A request context of 04 section 8.1 for conformance builds: the assistant message `msg`
#' followed by one result per tool call, with the tools those calls name
#' @noRd
adp_check_context = function(msg = NULL, tool_choice = "auto") {
  calls = list()
  if (!is.null(msg)) calls = Filter(function(b) identical(b$type, "tool_call"), msg$content)
  tool_names = unique(c("read", vapply(calls, function(b) b$name, "")))
  tools = lapply(tool_names, function(n) {
    list(name = n, description = "A conformance fixture tool.",
         input_schema = list(type = "object", properties = json_obj()))
  })
  msgs = list(msg_user("Run the conformance fixture.", timestamp = 0))
  if (!is.null(msg)) {
    msgs[[2L]] = msg
    for (b in calls) {
      msgs[[length(msgs) + 1L]] = msg_tool_result(b$id, b$name, "ok", timestamp = 0)
    }
  }
  list(system = list(t0 = "You are a conformance fixture.", t1 = ""),
       tools_json = json_verbatim(json_encode(tools)), tools = list(), messages = msgs,
       cache_plan = list(anchors = c("t0", "project"), tail_ttl = "5m",
                         key = "gptr:000000000000"),
       params = list(max_tokens = 1024L, thinking = NULL, effort = NULL,
                     tool_choice = tool_choice, returns = NULL, temperature = NULL),
       session_id = "s0000000000", request_id = "q000000000000")
}

#' The opaque strings of a message that must reach the wire byte for byte (INFRA-07)
#' @noRd
adp_opaque_strings = function(msg) {
  quoted = character()
  verbatim = character()
  for (b in msg$content) {
    type = b$type %||% ""
    if (type == "thinking") quoted = c(quoted, b$signature, b$data)
    if (type == "tool_call") quoted = c(quoted, b$thought_signature)
    if (type == "text" && !is.null(b$signature) && !startsWith(b$signature, "{")) {
      quoted = c(quoted, b$signature)
    }
    if (type == "opaque") verbatim = c(verbatim, b$json)
  }
  list(quoted = quoted, verbatim = verbatim)
}

#' Byte-identical re-serialisation: the message and its JSON round trip (the session file)
#' build the same body, with and without the memo, and every opaque string is on the wire
#' verbatim
#' @noRd
adp_roundtrip = function(adapter, model, msg) {
  opts = list(base_url = "http://127.0.0.1:1", memo = NULL)
  b1 = adapter$build(model, adp_check_context(msg), opts)$body
  msg2 = msg_from_json(json_decode(json_encode(msg_to_json(msg))))
  b2 = adapter$build(model, adp_check_context(msg2), opts)$body
  memo = new.env(parent = emptyenv())
  mopts = list(base_url = "http://127.0.0.1:1", memo = memo)
  b3 = adapter$build(model, adp_check_context(msg), mopts)$body
  b4 = adapter$build(model, adp_check_context(msg), mopts)$body
  s = adp_opaque_strings(msg)
  needles = c(vapply(s$quoted, function(x) {
    q = json_encode(x)
    substr(q, 2L, nchar(q) - 1L)
  }, ""), s$verbatim)
  missing = needles[!vapply(needles, function(x) grepl(x, b1, fixed = TRUE), logical(1))]
  same = identical(b1, b2) && identical(b1, b3) && identical(b1, b4)
  message = ""
  if (length(missing)) message = "an opaque value is not on the wire verbatim"
  if (!same) message = "re-serialisation changed the request body"
  list(ok = same && !length(missing), message = message)
}

#' Is a forced tool choice in a request body? (Anthropic, Responses, Chat and Gemini shapes)
#' @noRd
adp_body_forced = function(body) {
  tc = body$tool_choice
  adp_forced(tc) || identical(tc, "required") || identical(tc, "any") ||
    identical(body$toolConfig$functionCallingConfig$mode, "ANY")
}

#' Does a list tool_choice stay off the wire while forced_tool_choice is FALSE? Checked with
#' the model capability set to FALSE and, for adapters whose own capability is FALSE, with a
#' model record that says nothing (IC-71)
#' @noRd
adp_check_tool_choice = function(adapter) {
  ctx = adp_check_context(NULL, tool_choice = list(type = "tool", name = "read"))
  opts = list(base_url = "http://127.0.0.1:1")
  model = adp_fixture_model(adapter$api)
  model$reasoning = FALSE
  model$capabilities$forced_tool_choice = FALSE
  ok = !adp_body_forced(json_decode(adapter$build(model, ctx, opts)$body))
  if (isFALSE(adapter$capabilities$forced_tool_choice)) {
    model$capabilities$forced_tool_choice = NULL
    ok = ok && !adp_body_forced(json_decode(adapter$build(model, ctx, opts)$body))
  }
  ok
}

#' The fixture directory of an api: `fixtures`, else fixtures/sse/<api> under the test
#' directory or the package sources
#' @noRd
adp_fixture_dir = function(api, fixtures = NULL) {
  cands = fixtures
  if (is.null(cands)) {
    cands = c(file.path("fixtures", "sse", api),
              file.path("tests", "testthat", "fixtures", "sse", api))
  }
  for (d in cands) if (nzchar(d) && dir.exists(d)) return(normalizePath(d, winslash = "/"))
  NULL
}

#' Compare an R value with a golden JSON file (key order ignored)
#' @noRd
adp_same_golden = function(x, path) {
  if (!file.exists(path)) return(FALSE)
  want = json_decode(read_utf8(path)$text)
  identical(canonical_json(json_decode(json_encode(x))), canonical_json(want))
}

#' Conformance of an adapter (04 section 7.12; the check.adapter service of gptr_check())
#'
#' Replays every fixture (`<case>.sse`, or `.ndjson`, `.json`, `.jsonl` by transport) whole,
#' byte by byte and in three deterministic pseudo-random chunkings; compares the events and
#' the final message with `<case>.events.json` and `<case>.message.json`; checks one start
#' first and one terminal event last and that no R condition escapes; checks the byte-identical
#' re-serialisation of opaque data; and fails an adapter that sends a forced tool_choice while
#' forced_tool_choice is FALSE (IC-71). An adapter without a stream normaliser (an `inprocess`
#' generator, or a classifier whose `build`/`parse` live in `classify`) gives the one row
#' `adapter.replay`.
#' @param adapter A `gptr_adapter` spec.
#' @param fixtures A fixture directory, or NULL for fixtures/sse/<api>.
#' @return A `gptr_check` data frame (`target`, `check`, `ok`, `message`).
#' @noRd
check_adapter = function(adapter, fixtures = NULL) {
  api = adapter$api %||% adapter$name
  target = paste0("adapter:", api)
  rows = new.env(parent = emptyenv())
  rows$check = character()
  rows$ok = logical()
  rows$message = character()
  add = function(check, ok, message = "") {
    rows$check = c(rows$check, check)
    rows$ok = c(rows$ok, isTRUE(ok))
    rows$message = c(rows$message, if (isTRUE(ok)) "" else message)
  }
  frame = function() {
    df = data.frame(target = rep(target, length(rows$check)), check = rows$check, ok = rows$ok,
                    message = rows$message, stringsAsFactors = FALSE)
    class(df) = c("gptr_check", "data.frame")
    df
  }
  transport = adapter$transport %||% ""
  # nothing to replay: inprocess generators, and classifier adapters whose build and parse live
  # in `classify` (P13's typesafe-system-one: transport http_json, no stream normaliser)
  streams = transport %in% c("http_sse", "http_ndjson", "http_json", "process_jsonl")
  if (!streams || !is.function(adapter$parse)) {
    add("adapter.replay", TRUE)
    return(frame())
  }
  if (is.function(adapter$build)) {
    tc_ok = tryCatch(adp_check_tool_choice(adapter), error = function(e) FALSE)
    add("adapter.tool_choice", tc_ok,
        "a list tool_choice was sent although forced_tool_choice is FALSE")
  }
  dir = adp_fixture_dir(api, fixtures)
  ext = switch(transport, http_sse = "sse", http_ndjson = "ndjson", http_json = "json",
               process_jsonl = "jsonl")
  files = if (is.null(dir)) character() else
    list.files(dir, pattern = paste0("\\.", ext, "$"), full.names = TRUE)
  if (!length(files)) {
    add("adapter.fixtures", FALSE,
        paste0("no fixtures found for ", api, "; pass fixtures = <directory>"))
    return(frame())
  }
  model = adp_fixture_model(api, dir)
  for (f in sort(files)) {
    case = sub(paste0("\\.", ext, "$"), "", basename(f))
    bytes = readBin(f, "raw", file.size(f))
    whole = adp_replay(adapter, model, bytes, length(bytes))
    add(paste0("adapter.", case, ".no_condition"), is.null(whole$condition),
        if (is.null(whole$condition)) "" else conditionMessage(whole$condition))
    if (!is.null(whole$condition)) next
    types = vapply(whole$events, function(e) e$type %||% "", "")
    one_start = length(types) > 0L && types[[1L]] == "start" && sum(types == "start") == 1L
    one_term = sum(types %in% c("done", "error")) == 1L &&
      types[[length(types)]] %in% c("done", "error")
    add(paste0("adapter.", case, ".event_order"), one_start && one_term,
        paste0("event types: ", paste(types, collapse = " ")))
    golden = lapply(whole$events, adp_golden_event)
    add(paste0("adapter.", case, ".golden_events"),
        adp_same_golden(golden, file.path(dir, paste0(case, ".events.json"))),
        paste0("events differ from ", case, ".events.json"))
    add(paste0("adapter.", case, ".golden_message"),
        adp_same_golden(adp_golden_message(whole$message),
                        file.path(dir, paste0(case, ".message.json"))),
        paste0("the final message differs from ", case, ".message.json"))
    sizes = list(1L, adp_chunk_sizes(paste0(case, "-1")), adp_chunk_sizes(paste0(case, "-2")),
                 adp_chunk_sizes(paste0(case, "-3")))
    invariant = TRUE
    for (sz in sizes) {
      r = adp_replay(adapter, model, bytes, sz)
      if (!is.null(r$condition) || !identical(lapply(r$events, adp_golden_event), golden)) {
        invariant = FALSE
      }
    }
    add(paste0("adapter.", case, ".chunk_invariance"), invariant,
        "events differ between chunkings of the same bytes")
    ended = whole$message$stop_reason %||% "error"
    if (is.function(adapter$build) && !(ended %in% c("error", "aborted"))) {
      rt = tryCatch(adp_roundtrip(adapter, model, whole$message),
                    error = function(e) list(ok = FALSE, message = conditionMessage(e)))
      add(paste0("adapter.", case, ".roundtrip"), rt$ok, rt$message)
    }
  }
  frame()
}

on_load(ext_service_set("check.adapter", check_adapter, provided_by = "P12",
                        builtin = "anthropic"))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-anthropic")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 231 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/provider-anthropic.R tests/testthat/test-provider-anthropic.R
git commit -m "feat(provider): add check_adapter() and the check.adapter service"
```

---

### Task 4: Chat Completions compat flags, `<think>` splitter and normaliser

**Files:**
- Create: `R/provider-openai-completions.R`
- Modify: `tests/testthat/fixtures/sse/make_fixtures.R` (append) and, by running it, `tests/testthat/fixtures/sse/openai-completions/` (13 files)
- Test: `tests/testthat/test-provider-openai-completions.R` (create)

**Interfaces:**
- Consumes: the Task 1 core (`adp_state()`, `adp_open()`, `adp_delta()`, `adp_set_opaque()`, `adp_error()`, `adp_done()`, `adp_stream_error()`, `adp_finish_pending()`, `adp_normaliser()`, `adp_json_try()`, `adp_is_object()`); `provider_get(id)` (P05; the record's `id`, `base_url`, `local`, `compat`); `partial_json()`, `json_encode()`, `hash_sha256()` (P01). Tests use `gptr_register()`, `gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(), type = c("chat", "classifier", "cli"), headers = list(), discover = NULL, status = NULL, aliases = character(), local = FALSE, offline = FALSE, rate = NULL)` (P02).
- Produces: `compat_flags(provider, model)` (04 section 7.12; `provider` is a provider id or record, `model` a model record or `NULL`) -> a named list with every field of `compat_defaults()`; `compat_defaults()`, `compat_snake(x)`, `completions_model_name(model, compat)` (Azure deployments from `AZURE_OPENAI_DEPLOYMENT_NAME_MAP`), `think_splitter()` (`push(x)` -> list of `list(kind = "text" | "thinking", text)`, `flush()`), `completions_tool_id(id, compat, provider = "")`, `completions_error_info(err)`, `completions_normaliser(model, opts)` (the adapter's `parse`).

`compat_flags()` ports Pi's `detectCompat()`/`getCompat()` (report 09 section 3.3, `openai-completions.ts:1585-1726`): detection from the provider id and base URL (non-standard hosts, local servers, OpenRouter, DeepSeek, Mistral, Together, xAI, Azure), then the provider record's `compat` field by field, in P05's snake_case names or Pi's camelCase. OpenRouter forwards `cache_control` only for `anthropic/*` and `google/*` models (report 09 verification row 11, G4 section 2.6). The normaliser ports Pi's chunk loop (`openai-completions.ts:553-700`; report 09 section 3.2 and verification rows 12-14): text, reasoning in the first of `reasoning_content`, `reasoning` or `reasoning_text` (the field name is kept as the thinking block's signature so that a replay uses the same field), Mistral thinking content items, `reasoning_details` kept as an opaque block, tool-call fragments by `index` with their `id`, usage from the final chunk (`prompt_tokens` minus cached and cache-write tokens), the finish-reason map (`stop`/`end` -> `stop`, `length`, `tool_calls`/`function_call` -> `tool_use`, others -> `error` with the raw value), an `error` chunk (OpenRouter mid-stream errors) as a retryable or final failure, and a missing `finish_reason` as a truncated stream unless the compat record says `supports_finish_reason = FALSE`. With `think_tags` (Together's R1-style models) text passes through the streaming `<think>` splitter, which holds back a tag split across chunks (report 09 section 4.6).

Fixtures: `tools` (an OpenRouter comment line, `reasoning_content`, text, a tool call in fragments, a usage chunk, `[DONE]`), `think_tags` (`<think>` tags split across chunks), `error_chunk` (a mid-stream error chunk after a delta), `truncated` (no finish reason); `model.json` makes the fixture model `together/deepseek-r1` so the splitter is on.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/fixtures/sse/make_fixtures.R`:

```r
# ============================================================================================
# openai-completions (model.json: provider together, so the <think> splitter is on)
# ============================================================================================
k = "openai-completions"
dir.create(file.path(root, k), showWarnings = FALSE, recursive = TRUE)
write_text(file.path(root, k, "model.json"),
           '{"provider": "together", "id": "deepseek-r1", "input": ["text"]}\n')
chat_chunk = function(delta, finish = "null") {
  js(
    '{"id":"chatcmpl-1","object":"chat.completion.chunk","model":"deepseek-r1",',
    '"choices":[{"index":0,"delta":', delta, ',"finish_reason":', finish, "}]}"
  )
}

k_tools = c(
  ": OPENROUTER PROCESSING\n\n",
  dat(chat_chunk(js(
    '{"role":"assistant","content":"",',
    '"reasoning_content":"Need two lookups. "}'
  ))),
  dat(chat_chunk('{"content":"Checking both files"}')),
  dat(chat_chunk('{"content":"."}')),
  dat(chat_chunk(js(
    '{"tool_calls":[{"index":0,"id":"call_A1","type":"function",',
    '"function":{"name":"read","arguments":""}}]}'
  ))),
  dat(chat_chunk('{"tool_calls":[{"index":0,"function":{"arguments":"{\\"pa"}}]}')),
  dat(chat_chunk(js(
    '{"tool_calls":[{"index":0,"function":',
    '{"arguments":"th\\":\\"R/a.R\\"}"}}]}'
  ))),
  dat(chat_chunk(js(
    '{"tool_calls":[{"index":1,"id":"call_B2","type":"function",',
    '"function":{"name":"grep","arguments":"{\\"pattern\\":\\"nrow\\"}"}}]}'
  ))),
  dat(chat_chunk("{}", '"tool_calls"')),
  dat(js(
    '{"id":"chatcmpl-1","object":"chat.completion.chunk","model":"deepseek-r1",',
    '"choices":[],"usage":{"prompt_tokens":1500,"completion_tokens":96,',
    '"total_tokens":1596,"prompt_tokens_details":{"cached_tokens":1024},',
    '"completion_tokens_details":{"reasoning_tokens":32}}}'
  )),
  dat("[DONE]")
)
write_case(
  k, "tools", k_tools,
  list(e_start("chatcmpl-1"), e_open("thinking", 1L),
       e_delta("thinking", 1L, "Need two lookups. "), e_open("text", 2L),
       e_delta("text", 2L, "Checking both files"), e_delta("text", 2L, "."),
       e_tstart(3L, "call_A1", "read"), e_delta("toolcall", 3L, "{\"pa"),
       e_delta("toolcall", 3L, "th\":\"R/a.R\"}"),
       e_tstart(4L, "call_B2", "grep"), e_delta("toolcall", 4L, "{\"pattern\":\"nrow\"}"),
       e_end("thinking", 1L, g_think("Need two lookups. ", signature = "reasoning_content")),
       e_end("text", 2L, g_text("Checking both files.")),
       e_end("toolcall", 3L, g_tool("call_A1", "read", list(path = "R/a.R"))),
       e_end("toolcall", 4L, g_tool("call_B2", "grep", list(pattern = "nrow"))),
       e_done("tool_use")),
  g_msg("tool_use", "tool_calls", rid = "chatcmpl-1",
        content = list(g_think("Need two lookups. ", signature = "reasoning_content"),
                       g_text("Checking both files."),
                       g_tool("call_A1", "read", list(path = "R/a.R")),
                       g_tool("call_B2", "grep", list(pattern = "nrow"))),
        usage = g_usage(476, 96, 1024, reasoning = 32))
)

k_tags = c(
  dat(chat_chunk('{"role":"assistant","content":"<thi"}')),
  dat(chat_chunk('{"content":"nk>Plan: count rows.</th"}')),
  dat(chat_chunk('{"content":"ink>\\n\\nThere are 32 rows."}')),
  dat(chat_chunk("{}", '"stop"')),
  dat(js(
    '{"id":"chatcmpl-1","object":"chat.completion.chunk","model":"deepseek-r1",',
    '"choices":[],"usage":{"prompt_tokens":40,"completion_tokens":12,"total_tokens":52}}'
  )),
  dat("[DONE]")
)
write_case(
  k, "think_tags", k_tags,
  list(e_start("chatcmpl-1"), e_open("thinking", 1L),
       e_delta("thinking", 1L, "Plan: count rows."), e_open("text", 2L),
       e_delta("text", 2L, "\n\nThere are 32 rows."),
       e_end("thinking", 1L, g_think("Plan: count rows.")),
       e_end("text", 2L, g_text("\n\nThere are 32 rows.")), e_done("stop")),
  g_msg("stop", "stop", rid = "chatcmpl-1",
        content = list(g_think("Plan: count rows."), g_text("\n\nThere are 32 rows.")),
        usage = g_usage(40, 12))
)

k_error = c(
  dat(chat_chunk('{"role":"assistant","content":"Partial"}')),
  dat(js(
    '{"id":"chatcmpl-1","object":"chat.completion.chunk",',
    '"choices":[{"index":0,"delta":{},"finish_reason":"error"}],',
    '"error":{"code":502,"message":"Upstream provider failed"}}'
  ))
)
write_case(
  k, "error_chunk", k_error,
  list(e_start("chatcmpl-1"), e_open("text", 1L), e_delta("text", 1L, "Partial"),
       e_error("overloaded", 502L)),
  g_msg("error", err = "Upstream provider failed", rid = "chatcmpl-1",
        content = list(g_text("Partial")))
)

write_case(
  k, "truncated", dat(chat_chunk('{"role":"assistant","content":"Half"}')),
  list(e_start("chatcmpl-1"), e_open("text", 1L), e_delta("text", 1L, "Half"),
       e_error("network")),
  g_msg("error", err = "The stream ended without a finish_reason.", rid = "chatcmpl-1",
        content = list(g_text("Half")))
)
```

Run it again (it rewrites every fixture byte for byte and adds the new directory):

```bash
Rscript --vanilla tests/testthat/fixtures/sse/make_fixtures.R
ls tests/testthat/fixtures/sse/openai-completions | wc -l
```

Expected: the count is `13` (four cases with three files each, plus `model.json`); `git status --short tests/testthat/fixtures/sse` lists only the new directory and the modified generator.

Create `tests/testthat/test-provider-openai-completions.R`:

```r
# Tests for R/provider-openai-completions.R (plan P12): compat flags, the <think> splitter,
# tool ids, the openai-completions normaliser and request body.
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

api = "openai-completions"

# ---- compat flags, the <think> splitter and tool ids (Task 4) ---------------------------------

test_that("compat_flags() combines detection with the provider records of P05 (09 section 3.3)", {
  ds = compat_flags("deepseek", list(id = "deepseek-v4-pro"))
  expect_identical(ds$thinking_format, "deepseek")
  expect_true(ds$requires_reasoning_content)
  expect_identical(ds$max_tokens_field, "max_tokens")
  expect_false(ds$supports_store)
  ms = compat_flags("mistral", list(id = "devstral-medium-latest"))
  expect_identical(ms$tool_id, "alnum9")
  expect_true(ms$thinking_in_content)
  az = compat_flags("azure", list(id = "gpt-6-sol"))
  expect_identical(az$auth_header, "api-key")
  expect_true(az$deployment_model)
  ol = compat_flags("ollama", list(id = "qwen3:8b"))
  expect_false(ol$supports_store)
  expect_false(ol$supports_tool_choice)
  expect_identical(ol$max_tokens_field, "max_tokens")
  expect_true(compat_flags("together", list(id = "deepseek-r1"))$think_tags)
  groq = compat_flags("groq", list(id = "openai/gpt-oss-120b"))
  expect_identical(groq$max_tokens_field, "max_completion_tokens")
  expect_false(groq$requires_tool_result_name)
  expect_true(compat_flags("openai", NULL)$explicit_cache_mode)
  expect_setequal(names(ds), names(compat_defaults()))
})

test_that("OpenRouter sends cache_control only for Anthropic and Google models (G4 3.7)", {
  expect_identical(compat_flags("openrouter", list(id = "anthropic/claude-sonnet-5-5"))$
                     cache_control_format, "anthropic")
  expect_identical(compat_flags("openrouter", list(id = "google/gemini-3.8-flash"))$
                     cache_control_format, "anthropic")
  expect_identical(compat_flags("openrouter", list(id = "meta/llama-5"))$cache_control_format,
                   "none")
  expect_identical(compat_flags("openrouter", list(id = "x/y"))$session_affinity, "openrouter")
})

test_that("compat_flags() applies a record's compat in snake_case or Pi's camelCase", {
  rec = list(id = "corp", base_url = "https://llm.corp.example/v1",
             compat = list(maxTokensField = "max_tokens", requires_tool_result_name = TRUE,
                           requiresReasoningContentOnAssistantMessages = TRUE,
                           base_url_env = "IGNORED"))
  cf = compat_flags(rec, list(id = "corp-large"))
  expect_identical(cf$max_tokens_field, "max_tokens")
  expect_true(cf$requires_tool_result_name)
  expect_true(cf$requires_reasoning_content)
  expect_null(cf$base_url_env)
  expect_false(compat_flags(list(id = "x", base_url = "https://api.together.xyz/v1"),
                            list(id = "m"))$supports_store)
})

test_that("Azure deployments come from AZURE_OPENAI_DEPLOYMENT_NAME_MAP (09 section 2.5)", {
  withr::local_envvar(AZURE_OPENAI_DEPLOYMENT_NAME_MAP = "gpt-6-sol=prod-sol, other=x")
  cf = compat_flags("azure", list(id = "gpt-6-sol"))
  expect_identical(completions_model_name(list(id = "gpt-6-sol"), cf), "prod-sol")
  expect_identical(completions_model_name(list(id = "gpt-6-luna"), cf), "gpt-6-luna")
  expect_identical(completions_model_name(list(id = "gpt-6-sol"),
                                          compat_flags("groq", list(id = "m"))), "gpt-6-sol")
})

test_that("the <think> splitter routes tagged text to thinking across any chunking", {
  text = "<think>Plan: count rows.</think>The answer is 32."
  for (size in c(1L, 2L, 3L, 5L, 7L, 100L)) {
    sp = think_splitter()
    segs = list()
    for (s in seq(1L, nchar(text), by = size)) {
      segs = c(segs, sp$push(substr(text, s, s + size - 1L)))
    }
    segs = c(segs, sp$flush())
    kinds = vapply(segs, function(x) x$kind, "")
    texts = vapply(segs, function(x) x$text, "")
    expect_identical(paste(texts[kinds == "thinking"], collapse = ""), "Plan: count rows.")
    expect_identical(paste(texts[kinds == "text"], collapse = ""), "The answer is 32.")
  }
  sp = think_splitter()
  expect_identical(sp$push("a <thi"), list(list(kind = "text", text = "a ")))
  expect_identical(sp$flush(), list(list(kind = "text", text = "<thi")))
})

test_that("completions_tool_id() keeps ids within each provider's rules", {
  cf = compat_flags("groq", list(id = "m"))
  expect_identical(completions_tool_id("call_9Zx8Yw7Vu6|fc_0a1b2c", cf),
                   "call_9Zx8Yw7Vu6_fc_0a1b2c")
  long = completions_tool_id(paste0("call_", strrep("a", 40), "|fc_", strrep("b", 40)), cf)
  expect_lte(nchar(long), 40L)
  expect_match(long, "^[A-Za-z0-9_-]+$")
  nine = completions_tool_id("toolu_01A", compat_flags("mistral", list(id = "m")))
  expect_match(nine, "^[A-Za-z0-9]{9}$")
  expect_identical(completions_tool_id("toolu_01A", compat_flags("mistral", list(id = "m"))),
                   nine)
  expect_identical(nchar(completions_tool_id(strrep("c", 50), cf, "openai")), 40L)
})

# ---- the normaliser (Task 4) -------------------------------------------------------------------

test_that("completions fixtures give the golden events and final messages (INFRA-02)", {
  expect_all_golden(api, completions_normaliser)
})

test_that("completions events do not depend on how the bytes are chunked (INFRA-23)", {
  for (case in c("tools", "think_tags", "error_chunk")) {
    expect_chunk_invariant(api, completions_normaliser, case)
  }
})

test_that("a mid-stream error chunk and a truncated stream each give one error event", {
  for (case in c("error_chunk", "truncated")) {
    ev = replay_case(api, completions_normaliser, case)$events
    expect_one_terminal(ev)
    expect_identical(ev[[length(ev)]]$type, "error")
    expect_identical(ev[[length(ev)]]$message$content[[1L]]$type, "text")
  }
})

test_that("a missing finish_reason is inferred only when the compat record says so", {
  off = gptr_register(gptr_provider("corpx", api = "openai-completions",
                                    base_url = "http://127.0.0.1:9/v1",
                                    compat = list(supports_finish_reason = FALSE),
                                    local = TRUE, offline = TRUE))
  withr::defer(off())
  log = event_log()
  n = completions_normaliser(test_model(api, provider = "corpx"), list(emit = log$emit))
  n$push(list(data = '{"id":"c1","choices":[{"index":0,"delta":{"content":"ok"}}]}'))
  msg = n$finish()
  expect_identical(msg$stop_reason, "stop")
  expect_identical(log$events[[length(log$events)]]$type, "done")
})

test_that("Mistral thinking arrives as content items and becomes a thinking block", {
  log = event_log()
  n = completions_normaliser(test_model(api, provider = "mistral"), list(emit = log$emit))
  n$push(list(data = paste0('{"id":"m1","choices":[{"index":0,"delta":{"content":[',
                            '{"type":"thinking","thinking":[{"type":"text","text":"Hmm."}]},',
                            '{"type":"text","text":"Done."}]}}]}')))
  n$push(list(data = '{"id":"m1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}'))
  msg = n$finish()
  expect_identical(vapply(msg$content, function(b) b$type, ""), c("thinking", "text"))
  expect_identical(msg$content[[1L]]$thinking, "Hmm.")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-openai-completions")'`
Expected: `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 1 ]`, with errors such as ``could not find function "compat_flags"``.

- [ ] **Step 3: Write the implementation**

Create `R/provider-openai-completions.R`:

```r
# The openai-completions adapter (P12): OpenAI-compatible Chat Completions for OpenRouter,
# Groq, DeepSeek, Mistral, Together, xAI, Cerebras, Fireworks, the local servers, Azure and
# Bedrock, driven by the compat record of report 09 section 3.3 (Pi's OpenAICompletionsCompat
# and detectCompat(), openai-completions.ts:1585-1726) and a streaming <think> splitter
# (09 section 4.6). The normaliser is adapted from the verified prototypes of report 09
# section 5.1 and report 03 section 5.3 (verification log rows 11-14 applied: cache_control
# only for OpenRouter, the finish-reason map, thinking as a text-part array).

#' The compat fields and their defaults (snake_case forms of Pi's OpenAICompletionsCompat;
#' the names P05's provider records use)
#' @noRd
compat_defaults = function() {
  list(supports_store = TRUE, supports_developer_role = TRUE,
       supports_reasoning_effort = TRUE, supports_usage_in_streaming = TRUE,
       supports_finish_reason = TRUE, supports_strict_mode = FALSE, supports_tool_choice = TRUE,
       max_tokens_field = "max_completion_tokens", requires_tool_result_name = FALSE,
       requires_assistant_after_tool_result = FALSE, requires_thinking_as_text = FALSE,
       requires_reasoning_content = FALSE, thinking_format = "openai",
       thinking_in_content = FALSE, think_tags = FALSE, cache_control_format = "none",
       session_affinity = "none", image_mode = "base64", tool_id = "default",
       auth_header = "authorization", deployment_model = FALSE, explicit_cache_mode = FALSE)
}

#' Pi's camelCase compat names -> the snake_case field names of compat_defaults()
#' @noRd
compat_snake = function(x) {
  alias = c(requiresReasoningContentOnAssistantMessages = "requires_reasoning_content",
            sessionAffinityFormat = "session_affinity",
            supportsExplicitPromptCacheMode = "explicit_cache_mode")
  out = ifelse(x %in% names(alias), alias[x], x)
  tolower(gsub("([a-z0-9])([A-Z])", "\\1_\\2", out))
}

#' The compat record of a provider and model (04 section 7.12; report 09 section 3.3)
#'
#' Field names, `max_tokens` vs `max_completion_tokens`, reasoning replay, tool-id rules and
#' image and auth modes: detected from the provider id and base URL like Pi's detectCompat(),
#' then overridden field by field by the provider record's `compat` (snake_case or Pi's
#' camelCase names). OpenRouter forwards `cache_control` only to Anthropic and Google models
#' (G4 sections 2.6 and 3.7), so other OpenRouter model ids get `cache_control_format = "none"`.
#' @param provider A provider id (chr(1)) or a provider record.
#' @param model A model record (04 section 4.9) or NULL.
#' @return A named list with the fields of compat_defaults().
#' @noRd
compat_flags = function(provider, model) {
  rec = if (is.character(provider)) provider_get(provider) else provider
  id = if (is.character(provider)) provider else rec$id %||% rec$name %||% ""
  base = tolower(rec$base_url %||% "")
  mid = tolower(model$id %||% "")
  out = compat_defaults()
  hosts = paste0("cerebras\\.ai|api\\.x\\.ai|together\\.(ai|xyz)|deepseek\\.com|api\\.z\\.ai|",
                 "moonshot|nvidia\\.com|chutes\\.ai")
  nonstd = id %in% c("cerebras", "xai", "together", "deepseek", "zai", "moonshot", "nvidia",
                     "chutes", "fireworks", "mistral") || grepl(hosts, base)
  local = id %in% c("ollama", "lmstudio", "llamacpp", "vllm") || isTRUE(rec$local)
  openrouter = identical(id, "openrouter") || grepl("openrouter\\.ai", base)
  if (nonstd || local) {
    out$supports_store = FALSE
    out$supports_developer_role = FALSE
  }
  if (local) {
    out$supports_reasoning_effort = id %in% c("ollama", "vllm")
    out$max_tokens_field = "max_tokens"
  }
  if (openrouter) {
    out$supports_store = FALSE
    out$thinking_format = "openrouter"
    out$session_affinity = "openrouter"
    out$supports_developer_role = grepl("^(anthropic|openai)/", mid)
    out$cache_control_format = "anthropic"
  }
  if (id == "deepseek") {
    out$thinking_format = "deepseek"
    out$requires_reasoning_content = TRUE
    out$max_tokens_field = "max_tokens"
  }
  if (id == "mistral") {
    out$tool_id = "alnum9"
    out$thinking_in_content = TRUE
  }
  if (id == "together") {
    out$thinking_format = "together"
    out$max_tokens_field = "max_tokens"
    out$think_tags = TRUE
  }
  if (id == "xai") out$supports_reasoning_effort = FALSE
  if (id == "azure") {
    out$auth_header = "api-key"
    out$deployment_model = TRUE
  }
  if (id == "openai") out$explicit_cache_mode = TRUE
  over = rec$compat
  if (length(over)) {
    names(over) = compat_snake(names(over))
    for (k in intersect(names(over), names(out))) if (!is.null(over[[k]])) out[[k]] = over[[k]]
  }
  if (openrouter && !grepl("^(anthropic|google)/", mid)) out$cache_control_format = "none"
  out
}

#' The model name sent to the API: Azure deployments through AZURE_OPENAI_DEPLOYMENT_NAME_MAP
#' (`model=deployment,model2=dep2`, report 09 section 2.5), else the model id
#' @noRd
completions_model_name = function(model, compat) {
  if (!isTRUE(compat$deployment_model)) return(model$id)
  map = Sys.getenv("AZURE_OPENAI_DEPLOYMENT_NAME_MAP", "")
  if (!nzchar(map)) return(model$id)
  pairs = strsplit(strsplit(map, ",", fixed = TRUE)[[1L]], "=", fixed = TRUE)
  for (p in pairs) {
    if (length(p) == 2L && identical(trimws(p[[1L]]), model$id)) return(trimws(p[[2L]]))
  }
  model$id
}

#' A streaming <think>...</think> splitter: `push(x)` returns segments list(kind, text), with
#' tags that may be split across chunks held back; `flush()` returns the rest
#' @noRd
think_splitter = function() {
  st = new.env(parent = emptyenv())
  st$inside = FALSE
  st$hold = ""
  kind = function() if (st$inside) "thinking" else "text"
  push = function(x) {
    buf = paste0(st$hold, x)
    st$hold = ""
    out = list()
    repeat {
      tag = if (st$inside) "</think>" else "<think>"
      pos = regexpr(tag, buf, fixed = TRUE)
      if (pos > 0L) {
        before = substr(buf, 1L, pos - 1L)
        if (nzchar(before)) out[[length(out) + 1L]] = list(kind = kind(), text = before)
        buf = substr(buf, pos + nchar(tag), nchar(buf))
        st$inside = !st$inside
        next
      }
      keep = 0L
      for (k in seq_len(min(nchar(tag) - 1L, nchar(buf)))) {
        if (endsWith(buf, substr(tag, 1L, k))) keep = k
      }
      emit = substr(buf, 1L, nchar(buf) - keep)
      st$hold = substr(buf, nchar(buf) - keep + 1L, nchar(buf))
      if (nzchar(emit)) out[[length(out) + 1L]] = list(kind = kind(), text = emit)
      break
    }
    out
  }
  flush = function() {
    out = if (nzchar(st$hold)) list(list(kind = kind(), text = st$hold)) else list()
    st$hold = ""
    out
  }
  list(push = push, flush = flush)
}

#' Chat Completions tool-call ids: `call|item` ids joined and capped at 40 characters with a
#' hash suffix, Mistral's 9 alphanumeric characters, OpenAI's 40-character cap (Pi 1194-1218)
#' @noRd
completions_tool_id = function(id, compat, provider = "") {
  if (identical(compat$tool_id, "alnum9")) {
    if (grepl("^[A-Za-z0-9]{9}$", id)) return(id)
    return(substr(hash_sha256(id), 1L, 9L))
  }
  if (grepl("|", id, fixed = TRUE)) {
    p = strsplit(id, "|", fixed = TRUE)[[1L]]
    call = gsub("[^A-Za-z0-9_-]", "_", p[[1L]])
    item = if (length(p) > 1L) gsub("[^A-Za-z0-9_-]", "_", p[[2L]]) else ""
    combined = if (nzchar(item)) paste0(call, "_", item) else call
    if (nchar(combined) <= 40L) return(combined)
    return(paste0(substr(call, 1L, 31L), "_", substr(hash_sha256(id), 1L, 8L)))
  }
  if (identical(provider, "openai") && nchar(id) > 40L) return(substr(id, 1L, 40L))
  id
}

#' A Chat Completions error object -> class suffix, status and retryability (08 section 3.5)
#' @noRd
completions_error_info = function(err) {
  code = err$code
  status = if (is.numeric(code)) as.integer(code) else NA_integer_
  txt = tolower(paste(err$type %||% "", if (is.character(code)) code else ""))
  if (grepl("spend_limit|usage_limit|credit_balance|insufficient_quota", txt)) {
    return(list(class = "spend_cap", status = 429L, retry = FALSE))
  }
  if (identical(status, 429L) || grepl("rate_limit|slow_down", txt)) {
    return(list(class = "rate_limit", status = 429L, retry = TRUE))
  }
  if ((!is.na(status) && status >= 500L) || grepl("overload|server_error|unavailable", txt)) {
    return(list(class = "overloaded", status = if (is.na(status)) 503L else status, retry = TRUE))
  }
  list(class = "provider", status = status, retry = FALSE)
}

#' The openai-completions normaliser (04 section 8.1; Pi openai-completions.ts:553-700)
#' @noRd
completions_normaliser = function(model, opts) {
  st = adp_state(model, opts)
  compat = compat_flags(model$provider, model)
  cur = new.env(parent = emptyenv())
  cur$text = NULL
  cur$think = NULL
  cur$field = NULL
  cur$by_index = list()
  cur$by_id = list()
  cur$finish = FALSE
  cur$details = list()
  splitter = if (isTRUE(compat$think_tags)) think_splitter() else NULL

  add = function(kind, x) {
    if (!nzchar(x)) return(invisible(NULL))
    slot = if (kind == "thinking") "think" else "text"
    if (is.null(cur[[slot]])) {
      sig = if (kind == "thinking") cur$field else NULL
      assign(slot, adp_open(st, kind, signature = sig), envir = cur)
    }
    adp_delta(st, cur[[slot]], x)
  }

  add_text = function(x) {
    if (is.null(splitter)) return(add("text", x))
    for (seg in splitter$push(x)) add(seg$kind, seg$text)
  }

  on_tool = function(tc) {
    idx = if (!is.null(tc$index)) as.character(tc$index) else NULL
    i = if (!is.null(idx)) cur$by_index[[idx]] else NULL
    if (is.null(i) && is.character(tc$id) && nzchar(tc$id)) i = cur$by_id[[tc$id]]
    if (is.null(i)) {
      i = adp_open(st, "tool_call", id = tc$id %||% "", name = tc[["function"]]$name %||% "",
                   pj = partial_json())
    }
    if (!is.null(idx)) cur$by_index[[idx]] = i
    b = st$blocks[[i]]
    if (is.character(tc$id) && nzchar(tc$id)) {
      cur$by_id[[tc$id]] = i
      if (!nzchar(b$id %||% "")) b$id = tc$id
    }
    nm = tc[["function"]]$name
    if (!nzchar(b$name %||% "") && is.character(nm)) b$name = nm
    adp_delta(st, i, tc[["function"]]$arguments)
  }

  on_usage = function(u) {
    details = u[["prompt_tokens_details"]]
    cached = details[["cached_tokens"]] %||% u[["prompt_cache_hit_tokens"]] %||%
      u[["cached_tokens"]] %||% 0
    cwrite = details[["cache_write_tokens"]] %||% 0
    st$usage = list(input = max(0, (u[["prompt_tokens"]] %||% 0) - cached - cwrite),
                    output = u[["completion_tokens"]] %||% 0, cache_read = cached,
                    cache_write_5m = cwrite,
                    reasoning = u[["completion_tokens_details"]][["reasoning_tokens"]] %||% 0)
  }

  complete = function() {
    if (!is.null(splitter)) for (seg in splitter$flush()) add(seg$kind, seg$text)
    if (length(cur$details)) {
      i = adp_open(st, "opaque")
      adp_set_opaque(st, i, json_encode(cur$details))
    }
    if (!cur$finish) {
      if (isFALSE(compat$supports_finish_reason)) {
        has_tool = any(vapply(st$blocks, function(b) identical(b$type, "tool_call"), logical(1)))
        st$stop_reason = if (has_tool) "tool_use" else "stop"
      } else {
        adp_error(st, "The stream ended without a finish_reason.", class = "network")
        return(TRUE)
      }
    }
    adp_done(st)
    TRUE
  }

  push = function(ev) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    data = trimws(ev$data %||% "")
    if (!nzchar(data)) return(FALSE)
    if (identical(data, "[DONE]")) return(complete())
    ch = adp_json_try(data)
    if (!adp_is_object(ch)) {
      adp_error(st, paste0("Could not parse a chat completion chunk: ", substr(data, 1L, 200L)))
      return(TRUE)
    }
    if (!is.null(ch$error)) {
      info = completions_error_info(ch$error)
      return(adp_stream_error(st, opts, ch$error$message %||% "The provider reported an error.",
                              class = info$class, status = info$status, retryable = info$retry))
    }
    if (is.null(st$response_id) && !is.null(ch$id)) st$response_id = ch$id
    if (is.character(ch$model) && nzchar(ch$model) && !identical(ch$model, model$id)) {
      st$response_model = ch$model
    }
    if (!is.null(ch$usage)) on_usage(ch$usage)
    choice = if (length(ch$choices)) ch$choices[[1L]] else NULL
    if (is.null(choice)) return(FALSE)
    if (is.null(ch$usage) && !is.null(choice$usage)) on_usage(choice$usage)
    d = choice$delta
    if (!is.null(d)) {
      content = d$content
      if (is.character(content)) {
        add_text(content)
      } else if (is.list(content)) {
        for (item in content) {
          if (identical(item$type, "thinking")) {
            for (t in item$thinking %||% list()) add("thinking", t$text %||% "")
          } else if (is.character(item$text)) {
            add_text(item$text)
          }
        }
      }
      for (f in c("reasoning_content", "reasoning", "reasoning_text")) {
        v = d[[f]]
        if (is.character(v) && nzchar(v)) {
          cur$field = cur$field %||% f
          add("thinking", v)
          break
        }
      }
      if (length(d$reasoning_details)) cur$details = c(cur$details, d$reasoning_details)
      for (tc in d$tool_calls %||% list()) on_tool(tc)
    }
    fr = choice$finish_reason
    if (!is.null(fr)) {
      cur$finish = TRUE
      st$raw_stop = fr
      st$stop_reason = switch(fr, stop = , end = "stop", length = "length",
                              tool_calls = , function_call = "tool_use", "error")
      if (identical(st$stop_reason, "error")) {
        st$error_message = paste0("Provider finish_reason: ", fr)
      }
      has_tool = any(vapply(st$blocks, function(b) identical(b$type, "tool_call"), logical(1)))
      if (identical(st$stop_reason, "stop") && has_tool) st$stop_reason = "tool_use"
    }
    FALSE
  }

  finish = function() {
    if (st$terminal) return(st$final)
    if (!is.null(st$pending)) return(adp_finish_pending(st))
    complete()
    st$final
  }

  adp_normaliser(st, push, finish)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-openai-completions")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 89 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-openai-completions.R tests/testthat/test-provider-openai-completions.R tests/testthat/fixtures/sse/make_fixtures.R tests/testthat/fixtures/sse/openai-completions
git commit -m "feat(provider): add compat flags, the think splitter and the chat completions normaliser"
```

---

### Task 5: Chat Completions request bodies and `builtin:openai-compat`

**Files:**
- Modify: `R/provider-openai-completions.R` (append)
- Test: `tests/testthat/test-provider-openai-completions.R` (append)

**Interfaces:**
- Consumes: the Task 2 request helpers (`adp_memo()`, `adp_msg_key()`, `adp_tools_json()`, `adp_body()`, `adp_cache_plan()`, `adp_anchor_index()`, `adp_same_model()`, `adp_images_ok()`, `adp_image_note()`, `adp_header_secret()`, `adp_url()`, `adp_provider_headers()`, `adp_returns_instruction()`, `adp_forced()`, `adp_forced_ok()`, `adp_operator_text()`, `adp_has_tool_calls()`), `compat_flags()` and `completions_tool_id()` (Task 4), `gptr_adapter()`, `ext_declare_builtin()`, `on_load()`, `json_encode()`, `json_obj()`, `json_verbatim()` (P01/P02); `check_adapter()` (Task 3) and `gptr_check()` (P02) in the tests.
- Produces: `completions_build(model, context, opts)`, `completions_caps()`, `completions_user()`, `completions_assistant()`, `completions_tool_results()`, `completions_tools()`, `completions_thinking()`, `builtin_openai_compat(gptr)` and the registered adapter `openai-completions`.

Body rules (report 09 sections 3.2-3.4 and verification rows 13-14, 41-45; G4 section 3.7): key order `model`, `stream`, `stream_options` (`include_usage`), `store` (`false` where supported), the max-tokens field named by the compat record, thinking fields per `thinking_format` (`openai` `reasoning_effort`, `openrouter` `reasoning.effort`, `deepseek` `thinking.type`, `zai`, `qwen`, `qwen-chat-template`, `together` `reasoning.enabled`), `tool_choice`, the declared request params, `tools` (the frozen array converted once per session to `{type: "function", function: {...}}`; `tools: []` when there are no tools but the history holds tool calls), `messages` last. One system message (`developer` for reasoning models where supported) holds T0 and T1; with an OpenRouter Anthropic or Google model and a plan that names them, the system's last part and the anchored project block carry `cache_control: {type: "ephemeral"}`, and the session id goes in `x-session-id`. Reasoning is replayed only to the same model in the field it arrived in (DeepSeek forces `reasoning_content: ""` on replayed assistant messages); tool results become `tool` messages with ids within each host's rules (Mistral 9 alphanumeric characters), and their images follow as one user message (`images_in_results = FALSE`); operator messages and `returns` instructions are user messages. Azure sends the key as `api-key`, every other host as `Authorization: Bearer`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-provider-openai-completions.R`:

```r
# ---- the request body and the built-in (Task 5) ------------------------------------------------

completions_turn2 = function(model) {
  asst = msg_assistant(list(block_thinking("Need the row count.", signature = "reasoning_content"),
                            block_text("Checking."),
                            block_tool_call("call_A1", "r", list(code = "nrow(d)"))),
                       api = api, provider = model$provider, model = model$id,
                       stop_reason = "tool_use", timestamp = 2)
  # first_message() comes from replay_helpers.R, sourced at run time where lintr cannot see it
  first = first_message() # nolint: object_usage_linter.
  list(first, asst, msg_tool_result("call_A1", "r", "[1] 32", timestamp = 3))
}

test_that("completions bodies: one system message, converted tools, the messages last", {
  model = test_model(api, provider = "groq", id = "openai/gpt-oss-120b")
  req = completions_build(model, ctx_fixture(list(first_message())),
                          list(base_url = "https://api.groq.com/openai/v1"))
  body = json_decode(req$body)
  expect_identical(names(body), c("model", "stream", "stream_options", "store",
                                  "max_completion_tokens", "tools", "messages"))
  expect_equal(body$stream_options, list(include_usage = TRUE))
  expect_identical(body$messages[[1L]]$role, "developer")
  expect_identical(body$messages[[1L]]$content, "T0 static sections.\n\nT1 catalogs.")
  expect_identical(body$tools[[2L]]$`function`$name, "r")
  expect_identical(body$tools[[2L]]$`function`$parameters$required, list("code"))
  expect_identical(req$url, "https://api.groq.com/openai/v1/chat/completions")
})

test_that("OpenRouter Anthropic models get cache_control on the system and project blocks", {
  model = test_model(api, provider = "openrouter", id = "anthropic/claude-sonnet-5-5")
  req = completions_build(model, ctx_fixture(list(first_message())), list())
  body = json_decode(req$body)
  sys = body$messages[[1L]]$content
  expect_equal(sys[[length(sys)]]$cache_control, list(type = "ephemeral"))
  user = body$messages[[2L]]$content
  expect_equal(user[[1L]]$cache_control, list(type = "ephemeral"))
  expect_null(user[[2L]]$cache_control)
  expect_identical(req$headers$`x-session-id`, "s0123456789")
  expect_identical(req$headers$`X-OpenRouter-Title`, "gptr")
  none = list(anchors = character(), tail_ttl = "5m", key = "gptr:0123456789ab")
  expect_false(grepl("cache_control",
                     completions_build(model, ctx_fixture(list(first_message()), cache_plan = none),
                                       list())$body, fixed = TRUE))
  model$id = "meta/llama-5"
  expect_false(grepl("cache_control", completions_build(model, ctx_fixture(list(first_message())),
                                                        list())$body, fixed = TRUE))
})

test_that("the default cache policy anchors the OpenRouter system and project blocks", {
  plan = default_plan(api)
  expect_identical(plan$anchors, c("t0", "project"))
  model = test_model(api, provider = "openrouter", id = "google/gemini-3.8-flash")
  body = json_decode(completions_build(model, ctx_fixture(list(first_message()), cache_plan = plan),
                                       list())$body)
  sys = body$messages[[1L]]$content
  expect_equal(sys[[length(sys)]]$cache_control, list(type = "ephemeral"))
  expect_equal(body$messages[[2L]]$content[[1L]]$cache_control, list(type = "ephemeral"))
  groq = test_model(api, provider = "groq", id = "openai/gpt-oss-120b")
  expect_false(grepl("cache_control",
                     completions_build(groq, ctx_fixture(list(first_message()), cache_plan = plan),
                                       list())$body, fixed = TRUE))
})

test_that("reasoning is replayed in its own field to the same model; DeepSeek forces the field", {
  model = test_model(api, provider = "together", id = "deepseek-r1")
  body = json_decode(completions_build(model, ctx_fixture(completions_turn2(model)), list())$body)
  asst = body$messages[[3L]]
  expect_identical(asst$reasoning_content, "Need the row count.")
  expect_identical(asst$content, "Checking.")
  expect_identical(asst$tool_calls[[1L]]$`function`$arguments, "{\"code\":\"nrow(d)\"}")
  expect_identical(body$messages[[4L]], list(role = "tool", tool_call_id = "call_A1",
                                             content = "[1] 32"))
  ds = test_model(api, provider = "deepseek", id = "deepseek-v4-pro")
  msgs = completions_turn2(test_model(api, provider = "other", id = "x"))
  asst = json_decode(completions_build(ds, ctx_fixture(msgs), list())$body)$messages[[3L]]
  expect_identical(asst$reasoning_content, "")
})

test_that("tool-result images follow as one user message; Mistral ids are 9 characters", {
  model = test_model(api, provider = "mistral", id = "pixtral-large")
  msgs = completions_turn2(model)
  msgs[[3L]] = msg_tool_result("call_A1", "r", list(block_text("plot drawn"),
                                                    block_image(png_b64())))
  body = json_decode(completions_build(model, ctx_fixture(msgs), list())$body)
  tool = body$messages[[4L]]
  expect_identical(tool$role, "tool")
  expect_match(tool$tool_call_id, "^[A-Za-z0-9]{9}$")
  expect_identical(body$messages[[3L]]$tool_calls[[1L]]$id, tool$tool_call_id)
  img = body$messages[[5L]]
  expect_identical(img$role, "user")
  expect_identical(img$content[[2L]]$image_url$url, paste0("data:image/png;base64,", png_b64()))
})

test_that("no tools but tool calls in history sends tools: []; max_tokens per compat", {
  model = test_model(api, provider = "deepseek", id = "deepseek-v4-pro")
  ctx = ctx_fixture(completions_turn2(model), params = list(max_tokens = 2000L))
  ctx$tools_json = NULL
  body = json_decode(completions_build(model, ctx, list())$body)
  expect_identical(body$tools, list())
  expect_identical(body$max_tokens, 2000L)
  expect_null(body$max_completion_tokens)
})

test_that("thinking formats, tool_choice and auth headers follow the compat record", {
  model = test_model(api, provider = "openrouter", id = "openai/gpt-6-sol")
  forced = list(type = "tool", name = "read")
  req = completions_build(model, ctx_fixture(list(msg_user("x")),
                                             params = list(thinking = "low",
                                                           tool_choice = forced)),
                          list(credential = fake_handle("OPENROUTER_API_KEY")))
  body = json_decode(req$body)
  expect_equal(body$reasoning, list(effort = "low"))
  expect_equal(body$tool_choice, list(type = "function", `function` = list(name = "read")))
  expect_identical(req$headers$authorization, list("Bearer ", fake_handle("OPENROUTER_API_KEY")))
  no = test_model(api, provider = "groq", capabilities = list(forced_tool_choice = FALSE))
  body = json_decode(completions_build(no, ctx_fixture(list(msg_user("x")),
                                                       params = list(tool_choice = forced)),
                                       list())$body)
  expect_null(body$tool_choice)
  ol = test_model(api, provider = "ollama", id = "qwen3:8b")
  body = json_decode(completions_build(ol, ctx_fixture(list(msg_user("x")),
                                                       params = list(tool_choice = "none")),
                                       list())$body)
  expect_null(body$tool_choice)
  az = test_model(api, provider = "azure", id = "gpt-6-sol")
  req = completions_build(az, ctx_fixture(list(msg_user("x"))),
                          list(credential = fake_handle("AZURE_OPENAI_API_KEY")))
  expect_identical(req$headers$`api-key`, fake_handle("AZURE_OPENAI_API_KEY"))
  expect_null(req$headers$authorization)
})

test_that("returns = becomes an instruction with auto tool choice (IC-71)", {
  model = test_model(api, provider = "groq", id = "openai/gpt-oss-120b")
  body = json_decode(completions_build(model, ctx_fixture(list(msg_user("x")),
                                                          params = list(returns = count_schema())),
                                       list())$body)
  last = body$messages[[length(body$messages)]]
  expect_identical(last$role, "user")
  expect_match(last$content, "JSON Schema", fixed = TRUE)
  expect_null(body$tool_choice)
  expect_null(body$response_format)
})

test_that("the frozen prefix stays byte-identical across turns (acceptance 4)", {
  model = test_model(api, provider = "groq", id = "openai/gpt-oss-120b")
  memo = new.env(parent = emptyenv())
  b1 = completions_build(model, ctx_fixture(list(first_message())), list(memo = memo))$body
  b2 = completions_build(model, ctx_fixture(completions_turn2(model)), list(memo = memo))$body
  expect_true(startsWith(b2, substr(b1, 1L, nchar(b1) - 2L)))
  expect_identical(b2, completions_build(model, ctx_fixture(completions_turn2(model)),
                                         list())$body)
})

test_that("builtin:openai-compat registers the adapter; check_adapter() and gptr_check() pass", {
  a = adapter_get(api)
  expect_identical(a$capabilities$tool_shape, "chat")
  expect_identical(a$capabilities$cache, "openrouter")
  expect_identical(a$capabilities$request_params, c("service_tier", "metadata", "user"))
  res = check_adapter(a, fixtures = sse_dir(api))
  expect_true(all(res$ok), label = paste(res$check[!res$ok], collapse = "; "))
  expect_true(all(gptr_check(a)$ok))
})

test_that("end to end on the mock server: a Chat Completions stream (skip on CRAN)", {
  skip_on_cran()
  srv = local_mock_server("chat_completions", n = 3L, interval = 0.02)
  r = mock_stream(srv)
  expect_identical(r$types, c("start", "text_start", rep("text_delta", 3L), "text_end", "done"))
  expect_identical(r$message$stop_reason, "stop")
  expect_identical(msg_text(r$message), "tok01 tok02 tok03 ")
  expect_identical(r$message$usage$input, 100)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-openai-completions")'`
Expected: `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 89 ]`, with errors such as ``could not find function "completions_build"``.

- [ ] **Step 3: Write the implementation**

Append to `R/provider-openai-completions.R`:

```r
#' Adapter capabilities of openai-completions (04 section 8.1; IC-69, IC-71)
#'
#' `cache = "openrouter"`: the default cache policy (P07) then anchors T0 and the project block;
#' the markers are written only for providers whose compat record has
#' `cache_control_format = "anthropic"` (OpenRouter's Anthropic and Google models) and ignored by
#' every other OpenAI-compatible host (G4 section 3.7).
#' @noRd
completions_caps = function() {
  list(images_in_results = FALSE, tool_addition = FALSE, structured_output = FALSE,
       reasoning_replay = TRUE, parallel_tools = TRUE, forced_tool_choice = TRUE,
       request_params = c("service_tier", "metadata", "user"), operator_role = "user",
       cache = "openrouter", max_tool_name = 64L, tool_shape = "chat")
}

#' Chat Completions content of a user message: a string, or text and image_url parts
#' @noRd
completions_user = function(m, model, mark_anchor, cc) {
  images = adp_images_ok(model)
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    if (type %in% c("text", "context") && nzchar(b$text)) {
      p = list(type = "text", text = b$text)
      if (cc && mark_anchor && type == "context" && isTRUE(b$anchor)) {
        p$cache_control = list(type = "ephemeral")
      }
      parts[[length(parts) + 1L]] = p
    } else if (type == "image") {
      url = paste0("data:", b$mime, ";base64,", b$data)
      parts[[length(parts) + 1L]] = if (images) {
        list(type = "image_url", image_url = list(url = url))
      } else {
        list(type = "text", text = adp_image_note())
      }
    }
  }
  if (!length(parts)) return(NULL)
  single = length(parts) == 1L && identical(parts[[1L]]$type, "text") &&
    is.null(parts[[1L]]$cache_control)
  if (single) return(list(role = "user", content = parts[[1L]]$text))
  list(role = "user", content = parts)
}

#' A Chat Completions assistant message: content a plain string (a text-part array only when
#' requires_thinking_as_text), reasoning replayed in the field it arrived in (Pi 1296-1396)
#' @noRd
completions_assistant = function(m, model, compat) {
  same = adp_same_model(m, model)
  texts = character()
  thinks = character()
  field = NULL
  calls = list()
  details = NULL
  for (b in m$content) {
    type = b$type %||% ""
    if (type == "text" && nzchar(trimws(b$text))) texts = c(texts, b$text)
    if (type == "thinking" && nzchar(trimws(b$thinking))) {
      thinks = c(thinks, b$thinking)
      field = field %||% b$signature
    }
    if (type == "tool_call") {
      args = if (length(b$arguments)) b$arguments else json_obj()
      calls[[length(calls) + 1L]] = list(id = completions_tool_id(b$id, compat, model$provider),
                                         type = "function",
                                         `function` = list(name = b$name,
                                                           arguments = json_encode(args)))
    }
    if (type == "opaque" && same) details = b$json
  }
  txt = paste(texts, collapse = "")
  as_text = length(thinks) && isTRUE(compat$requires_thinking_as_text)
  a = list(role = "assistant")
  if (as_text) {
    a$content = lapply(c(paste(thinks, collapse = "\n\n"), if (nzchar(txt)) txt),
                       function(x) list(type = "text", text = x))
  } else if (nzchar(txt)) {
    a$content = txt
  } else if (length(calls)) {
    a["content"] = if (isTRUE(compat$requires_assistant_after_tool_result)) list("") else list(NULL)
  } else {
    return(NULL)
  }
  if (length(calls)) a$tool_calls = calls
  fields = c("reasoning_content", "reasoning", "reasoning_text")
  if (length(thinks) && !as_text && same && isTRUE(field %in% fields)) {
    a[[field]] = paste(thinks, collapse = "\n")
  } else if (isTRUE(compat$requires_reasoning_content) && isTRUE(model$reasoning)) {
    a$reasoning_content = ""
  }
  if (!is.null(details)) a$reasoning_details = json_verbatim(details)
  a
}

#' Chat Completions messages of a group of tool results; images follow as one user message
#' @noRd
completions_tool_results = function(group, model, compat) {
  out = list()
  imgs = list()
  images = adp_images_ok(model)
  for (r in group) {
    txt = paste(vapply(Filter(function(b) identical(b$type, "text"), r$content),
                       function(b) b$text, ""), collapse = "\n")
    has_img = any(vapply(r$content, function(b) identical(b$type, "image"), logical(1)))
    content = if (nzchar(txt)) txt else if (has_img) "(see attached image)" else "(no tool output)"
    tm = list(role = "tool",
              tool_call_id = completions_tool_id(r$tool_call_id, compat, model$provider),
              content = content)
    if (isTRUE(compat$requires_tool_result_name)) tm$name = r$tool_name
    out[[length(out) + 1L]] = tm
    if (images) {
      for (b in Filter(function(b) identical(b$type, "image"), r$content)) {
        url = paste0("data:", b$mime, ";base64,", b$data)
        imgs[[length(imgs) + 1L]] = list(type = "image_url", image_url = list(url = url))
      }
    }
  }
  if (length(imgs)) {
    note = list(type = "text", text = "Attached image(s) from tool result:")
    out[[length(out) + 1L]] = list(role = "user", content = c(list(note), imgs))
  }
  out
}

#' Chat Completions tool definitions from the frozen Anthropic-shape array (04 section 9.2)
#' @noRd
completions_tools = function(tools, compat) {
  lapply(tools, function(t) {
    fn = list(name = t$name, description = t$description %||% "", parameters = t$input_schema)
    if (isTRUE(compat$supports_strict_mode)) fn$strict = FALSE
    list(type = "function", `function` = fn)
  })
}

#' The thinking request fields of a compat thinking_format (report 09 section 3.4)
#' @noRd
completions_thinking = function(head, model, params, compat) {
  if (!isTRUE(model$reasoning) || is.null(params$thinking)) return(head)
  level = params$thinking
  on = !identical(level, "off")
  eff = params$effort %||% (if (on) level else NULL)
  fmt = compat$thinking_format %||% "openai"
  if (fmt == "openrouter") {
    head$reasoning = list(effort = if (on) eff else "none")
  } else if (fmt == "deepseek") {
    head$thinking = list(type = if (on) "enabled" else "disabled")
    if (on && isTRUE(compat$supports_reasoning_effort)) head$reasoning_effort = eff
  } else if (fmt == "zai") {
    head$thinking = if (on) list(type = "enabled", clear_thinking = FALSE) else
      list(type = "disabled")
  } else if (fmt == "qwen") {
    head$enable_thinking = on
  } else if (fmt == "qwen-chat-template") {
    head$chat_template_kwargs = list(enable_thinking = on, preserve_thinking = TRUE)
  } else if (fmt == "together") {
    head$reasoning = list(enabled = on)
  } else if (isTRUE(compat$supports_reasoning_effort)) {
    if (on) {
      head$reasoning_effort = eff
    } else if ("off" %in% unlist(model$thinking_levels)) {
      head$reasoning_effort = "none"
    }
  }
  head
}

#' build() of the openai-completions adapter (04 section 8.1; G4 section 3.7: model, stream,
#' stream_options, tools, messages; OpenRouter session affinity and cache_control)
#' @noRd
completions_build = function(model, context, opts) {
  params = context$params %||% list()
  compat = compat_flags(model$provider, model)
  anchors = adp_cache_plan(context)$anchors %||% character()
  cc_ok = identical(compat$cache_control_format, "anthropic")
  cc_sys = cc_ok && any(c("t0", "t1") %in% anchors)
  cc = cc_ok && "project" %in% anchors
  msgs = context$messages %||% list()
  anchor_at = adp_anchor_index(msgs)

  head = list(model = completions_model_name(model, compat), stream = TRUE)
  if (isTRUE(compat$supports_usage_in_streaming)) head$stream_options = list(include_usage = TRUE)
  if (isTRUE(compat$supports_store)) head$store = FALSE
  if (!is.null(params$max_tokens)) head[[compat$max_tokens_field]] = as.integer(params$max_tokens)
  if (!is.null(params$temperature)) head$temperature = params$temperature
  head = completions_thinking(head, model, params, compat)
  tc = params$tool_choice
  if (isTRUE(compat$supports_tool_choice)) {
    if (identical(tc, "none")) {
      head$tool_choice = "none"
    } else if (adp_forced(tc) && adp_forced_ok(model, completions_caps()) &&
                 is.null(params$returns)) {
      head$tool_choice = if (identical(tc$type, "any")) "required" else
        list(type = "function", `function` = list(name = tc$name))
    }
  }
  for (f in completions_caps()$request_params) if (!is.null(params[[f]])) head[[f]] = params[[f]]

  extra = character()
  tj = adp_tools_json(opts, paste("openai-completions", compat$supports_strict_mode),
                      context$tools_json, function(tools) completions_tools(tools, compat))
  if (!is.null(tj)) {
    extra = c(extra, paste0("\"tools\":", tj))
  } else if (adp_has_tool_calls(msgs)) {
    extra = c(extra, "\"tools\":[]")
  }

  elements = character()
  t0 = context$system$t0 %||% ""
  t1 = context$system$t1 %||% ""
  role = if (isTRUE(model$reasoning) && isTRUE(compat$supports_developer_role)) "developer" else
    "system"
  if (nzchar(t0) || nzchar(t1)) {
    sys = if (cc_sys) {
      parts = list()
      if (nzchar(t0)) parts[[length(parts) + 1L]] = list(type = "text", text = t0)
      if (nzchar(t1)) parts[[length(parts) + 1L]] = list(type = "text", text = t1)
      parts[[length(parts)]]$cache_control = list(type = "ephemeral")
      list(role = role, content = parts)
    } else {
      list(role = role, content = paste(c(t0, t1)[nzchar(c(t0, t1))], collapse = "\n\n"))
    }
    elements = c(elements, json_encode(sys))
  }
  n = length(msgs)
  i = 1L
  while (i <= n) {
    m = msgs[[i]]
    r = m$role %||% ""
    if (r == "tool_result") {
      j = i
      while (j <= n && identical(msgs[[j]]$role, "tool_result")) j = j + 1L
      group = msgs[i:(j - 1L)]
      key = paste(c("openai-completions", "results", model$provider, model$id,
                    vapply(group, adp_msg_key, "")), collapse = "|")
      el = adp_memo(opts, key, function() {
        paste(vapply(completions_tool_results(group, model, compat), json_encode, ""),
              collapse = ",")
      })
      elements = c(elements, el)
      nxt = if (j <= n) msgs[[j]]$role %||% "" else "end"
      if (isTRUE(compat$requires_assistant_after_tool_result) && nxt %in% c("user", "operator")) {
        elements = c(elements, json_encode(list(role = "assistant",
                                                content = "I have processed the tool results.")))
      }
      i = j
      next
    }
    same = adp_same_model(m, model)
    mark = identical(i, anchor_at)
    key = paste("openai-completions", r, adp_msg_key(m), model$provider, model$id, same, mark,
                cc, sep = "|")
    el = adp_memo(opts, key, function() {
      x = NULL
      if (r == "user") x = completions_user(m, model, mark, cc)
      if (r == "assistant") x = completions_assistant(m, model, compat)
      if (r == "operator") {
        txt = adp_operator_text(m)
        if (nzchar(txt)) x = list(role = "user", content = txt)
      }
      if (is.null(x)) "" else json_encode(x)
    })
    if (nzchar(el)) elements = c(elements, el)
    i = i + 1L
  }
  if (!is.null(params$returns)) {
    elements = c(elements, json_encode(list(role = "user",
                                            content = adp_returns_instruction(params$returns))))
  }

  headers = list(`content-type` = "application/json", accept = "text/event-stream")
  cred = opts$credential
  if (!is.null(cred)) {
    if (identical(compat$auth_header, "api-key")) {
      headers$`api-key` = adp_header_secret(cred)
    } else {
      headers$authorization = adp_header_secret(cred, "Bearer ")
    }
  }
  if (identical(compat$session_affinity, "openrouter") && !is.null(context$session_id)) {
    headers$`x-session-id` = context$session_id
  }
  headers = c(headers, adp_provider_headers(model))

  list(url = adp_url(opts$base_url %||% "https://api.openai.com/v1", "chat/completions"),
       method = "POST", headers = headers,
       body = adp_body(head, extra, "messages", elements), stream = "sse")
}

#' builtin:openai-compat: registers the openai-completions adapter (04 sections 7.12, 10.3)
#' @noRd
builtin_openai_compat = function(gptr) {
  gptr$register(gptr_adapter("openai-completions", transport = "http_sse",
                             build = completions_build, parse = completions_normaliser,
                             capabilities = completions_caps()))
  invisible(NULL)
}

on_load(ext_declare_builtin("openai-compat", builtin_openai_compat))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-openai-completions")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 142 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-openai-completions.R tests/testthat/test-provider-openai-completions.R
git commit -m "feat(provider): build chat completions request bodies and register builtin:openai-compat"
```

---

### Task 6: Responses normaliser

**Files:**
- Create: `R/provider-openai-responses.R`
- Modify: `tests/testthat/fixtures/sse/make_fixtures.R` (append) and, by running it, `tests/testthat/fixtures/sse/openai-responses/` (15 files)
- Test: `tests/testthat/test-provider-openai-responses.R` (create)

**Interfaces:**
- Consumes: the Task 1 core (`adp_state()`, `adp_open()`, `adp_delta()`, `adp_close()`, `adp_set_opaque()`, `adp_buffer_text()`, `adp_error()`, `adp_done()`, `adp_stream_error()`, `adp_finish_pending()`, `adp_normaliser()`, `adp_json_try()`, `adp_is_object()`), `partial_json()`, `json_encode()` (P01).
- Produces: `responses_normaliser(model, opts)` (the adapter's `parse`), `responses_error_info(code)`, `responses_reasoning_item(item)`.

The normaliser follows report 08 sections 2.A, 3.2-3.3 and 5.7 with the verification-log fixes: a reasoning output item opens a thinking slot (summary text, streamed from `response.reasoning_summary_text.delta` with a blank line between summary parts) and an opaque slot holding the reasoning item for replay (`type`, `id`, `summary`, `encrypted_content`, `content`); the completed item comes from `response.output_item.done`, and an `encrypted_content` missing there is backfilled from `response.completed` (row 32, "the quirk is a missing `encrypted_content` on reasoning items"); a message item's `id` and `phase` are kept as the text block's signature `{"v":1,"id":...,"phase":...}` (Pi's text signature; row 37 "`phase` must be preserved"); a function call's id is `<call_id>|<fc_id>` (04 section 4.1: "provider id verbatim, e.g. `call_1|fc_2`"); usage is `input_tokens` minus cached and cache-write tokens (08 section 3.3); `response.completed` gives `stop` (or `tool_use` when the output holds calls), `response.incomplete` with `max_output_tokens` gives `length` and any other reason `error`; `response.failed` and the top-level `error` event are retryable (`server_error`, `server_is_overloaded`, `rate_limit_exceeded`, `slow_down`) or final (spend and quota codes are never retried, 08 section 3.5).

Fixtures: `reasoning_tools` (a reasoning item with a two-part summary and encrypted content, a `commentary` message, a function call streamed in fragments), `backfill` (`encrypted_content` only in `response.completed`), `failed`, `incomplete` (`max_output_tokens`), `truncated`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/fixtures/sse/make_fixtures.R`:

```r
# ============================================================================================
# openai-responses
# ============================================================================================
o = "openai-responses"
txt = "data frame \u00e9 \u2713."

rs_done = js(
  '{"id":"rs_fixture1","type":"reasoning",',
  '"summary":[{"type":"summary_text",',
  '"text":"**Planning** Need nrow of the data."}],',
  '"encrypted_content":"gAAAAB-fixture-opaque-blob==",',
  '"status":"completed"}'
)

msg_done = js(
  '{"id":"msg_fixture1","type":"message","role":"assistant",',
  '"status":"completed","phase":"commentary",',
  '"content":[{"type":"output_text","text":"Checking the ',
  txt,
  '","annotations":[]}]}'
)

fc_done = js(
  '{"id":"fc_fixture1","type":"function_call","status":"completed",',
  '"call_id":"call_fixture1","name":"r",',
  '"arguments":"{\\"code\\":\\"nrow(big_df)\\"}"}'
)

o_tools = c(
  ev("response.created", js(
    '{"type":"response.created","response":{"id":"resp_fixture1",',
    '"object":"response","status":"in_progress","model":"gpt-6-luna",',
    '"output":[]},"sequence_number":1}'
  )),
  ev("response.output_item.added", js(
    '{"type":"response.output_item.added","output_index":0,',
    '"item":{"id":"rs_fixture1","type":"reasoning","summary":[],',
    '"status":"in_progress"},"sequence_number":2}'
  )),
  ev("response.reasoning_summary_part.added", js(
    '{"type":"response.reasoning_summary_part.added",',
    '"item_id":"rs_fixture1","output_index":0,"summary_index":0,',
    '"part":{"type":"summary_text","text":""},"sequence_number":3}'
  )),
  ev("response.reasoning_summary_text.delta", js(
    '{"type":"response.reasoning_summary_text.delta",',
    '"item_id":"rs_fixture1","output_index":0,"summary_index":0,',
    '"delta":"**Planning** Need nrow ","sequence_number":4}'
  )),
  ev("response.reasoning_summary_text.delta", js(
    '{"type":"response.reasoning_summary_text.delta",',
    '"item_id":"rs_fixture1","output_index":0,"summary_index":0,',
    '"delta":"of the data.","sequence_number":5}'
  )),
  ev("response.output_item.done", js(
    '{"type":"response.output_item.done","output_index":0,"item":',
    rs_done,
    ',"sequence_number":6}'
  )),
  ev("response.output_item.added", js(
    '{"type":"response.output_item.added","output_index":1,',
    '"item":{"id":"msg_fixture1","type":"message","role":"assistant",',
    '"status":"in_progress","phase":"commentary","content":[]},',
    '"sequence_number":7}'
  )),
  ev("response.output_text.delta", js(
    '{"type":"response.output_text.delta","item_id":"msg_fixture1",',
    '"output_index":1,"content_index":0,"delta":"Checking the ",',
    '"sequence_number":8}'
  )),
  ev("response.output_text.delta", js(
    '{"type":"response.output_text.delta","item_id":"msg_fixture1",',
    '"output_index":1,"content_index":0,"delta":"',
    txt,
    '","sequence_number":9}'
  )),
  ev("response.output_item.done", js(
    '{"type":"response.output_item.done","output_index":1,"item":',
    msg_done,
    ',"sequence_number":10}'
  )),
  ev("response.output_item.added", js(
    '{"type":"response.output_item.added","output_index":2,',
    '"item":{"id":"fc_fixture1","type":"function_call",',
    '"status":"in_progress","call_id":"call_fixture1","name":"r",',
    '"arguments":""},"sequence_number":11}'
  )),
  ev("response.function_call_arguments.delta", js(
    '{"type":"response.function_call_arguments.delta",',
    '"item_id":"fc_fixture1","output_index":2,"delta":"{\\"code\\":",',
    '"sequence_number":12}'
  )),
  ev("response.function_call_arguments.delta", js(
    '{"type":"response.function_call_arguments.delta",',
    '"item_id":"fc_fixture1","output_index":2,',
    '"delta":"\\"nrow(big_df)\\"}","sequence_number":13}'
  )),
  ev("response.function_call_arguments.done", js(
    '{"type":"response.function_call_arguments.done",',
    '"item_id":"fc_fixture1","output_index":2,',
    '"arguments":"{\\"code\\":\\"nrow(big_df)\\"}","sequence_number":14}'
  )),
  ev("response.output_item.done", js(
    '{"type":"response.output_item.done","output_index":2,"item":',
    fc_done,
    ',"sequence_number":15}'
  )),
  ev("response.completed", js(
    '{"type":"response.completed","response":{"id":"resp_fixture1",',
    '"object":"response","status":"completed","model":"gpt-6-luna",',
    '"output":[',
    rs_done,
    ",",
    msg_done,
    ",",
    fc_done,
    '],"usage":{"input_tokens":812,',
    '"input_tokens_details":{"cached_tokens":512,"cache_write_tokens":0},',
    '"output_tokens":64,"output_tokens_details":{"reasoning_tokens":32},',
    '"total_tokens":876}},"sequence_number":16}'
  ))
)
rs_replay = js(
  '{"type":"reasoning","id":"rs_fixture1",',
  '"summary":[{"type":"summary_text",',
  '"text":"**Planning** Need nrow of the data."}],',
  '"encrypted_content":"gAAAAB-fixture-opaque-blob=="}'
)

msg_sig = '{"v":1,"id":"msg_fixture1","phase":"commentary"}'
plan = "**Planning** Need nrow of the data."
call_id = "call_fixture1|fc_fixture1"
write_case(
  o, "reasoning_tools", o_tools,
  list(e_start("resp_fixture1"), e_open("thinking", 1L),
       e_delta("thinking", 1L, "**Planning** Need nrow "),
       e_delta("thinking", 1L, "of the data."), e_end("thinking", 1L, g_think(plan)),
       e_open("text", 3L), e_delta("text", 3L, "Checking the "), e_delta("text", 3L, txt),
       e_end("text", 3L, g_text(paste0("Checking the ", txt), msg_sig)),
       e_tstart(4L, call_id, "r"), e_delta("toolcall", 4L, "{\"code\":"),
       e_delta("toolcall", 4L, "\"nrow(big_df)\"}"),
       e_end("toolcall", 4L, g_tool(call_id, "r", list(code = "nrow(big_df)"))),
       e_done("tool_use")),
  g_msg("tool_use", "completed", rid = "resp_fixture1", rmodel = "gpt-6-luna",
        content = list(g_think(plan), g_opaque(rs_replay),
                       g_text(paste0("Checking the ", txt), msg_sig),
                       g_tool(call_id, "r", list(code = "nrow(big_df)"))),
        usage = g_usage(300, 64, 512, reasoning = 32))
)

o_backfill = c(
  ev("response.created", js(
    '{"type":"response.created","response":{"id":"resp_b1",',
    '"status":"in_progress","model":"fixture-1","output":[]}}'
  )),
  ev("response.output_item.added", js(
    '{"type":"response.output_item.added","output_index":0,',
    '"item":{"id":"rs_b1","type":"reasoning","summary":[]}}'
  )),
  ev("response.reasoning_summary_text.delta", js(
    '{"type":"response.reasoning_summary_text.delta","output_index":0,',
    '"summary_index":0,"delta":"Thinking."}'
  )),
  ev("response.output_item.done", js(
    '{"type":"response.output_item.done","output_index":0,',
    '"item":{"id":"rs_b1","type":"reasoning",',
    '"summary":[{"type":"summary_text","text":"Thinking."}]}}'
  )),
  ev("response.output_item.added", js(
    '{"type":"response.output_item.added","output_index":1,',
    '"item":{"id":"msg_b1","type":"message","role":"assistant",',
    '"phase":"final_answer","content":[]}}'
  )),
  ev("response.output_text.delta", js(
    '{"type":"response.output_text.delta","output_index":1,',
    '"content_index":0,"delta":"Done."}'
  )),
  ev("response.completed", js(
    '{"type":"response.completed","response":{"id":"resp_b1",',
    '"status":"completed","model":"fixture-1","output":[{"id":"rs_b1",',
    '"type":"reasoning","summary":[{"type":"summary_text",',
    '"text":"Thinking."}],"encrypted_content":"gAAAAB-backfilled=="},',
    '{"id":"msg_b1","type":"message","role":"assistant",',
    '"status":"completed","phase":"final_answer",',
    '"content":[{"type":"output_text","text":"Done.",',
    '"annotations":[]}]}],"usage":{"input_tokens":100,',
    '"input_tokens_details":{"cached_tokens":0},"output_tokens":10,',
    '"output_tokens_details":{"reasoning_tokens":4}}}}'
  ))
)
rs_b1 = js(
  '{"type":"reasoning","id":"rs_b1","summary":[{"type":"summary_text",',
  '"text":"Thinking."}],"encrypted_content":"gAAAAB-backfilled=="}'
)

b1_sig = '{"v":1,"id":"msg_b1","phase":"final_answer"}'
write_case(
  o, "backfill", o_backfill,
  list(e_start("resp_b1"), e_open("thinking", 1L), e_delta("thinking", 1L, "Thinking."),
       e_end("thinking", 1L, g_think("Thinking.")), e_open("text", 3L),
       e_delta("text", 3L, "Done."), e_end("text", 3L, g_text("Done.", b1_sig)),
       e_done("stop")),
  g_msg("stop", "completed", rid = "resp_b1",
        content = list(g_think("Thinking."), g_opaque(rs_b1), g_text("Done.", b1_sig)),
        usage = g_usage(100, 10, reasoning = 4))
)

o_failed = c(
  ev("response.created", js(
    '{"type":"response.created","response":{"id":"resp_f1",',
    '"status":"in_progress","model":"fixture-1","output":[]}}'
  )),
  ev("response.output_item.added", js(
    '{"type":"response.output_item.added","output_index":0,',
    '"item":{"id":"msg_f1","type":"message","role":"assistant",',
    '"content":[]}}'
  )),
  ev("response.output_text.delta", js(
    '{"type":"response.output_text.delta","output_index":0,',
    '"content_index":0,"delta":"Partial"}'
  )),
  ev("response.failed", js(
    '{"type":"response.failed","response":{"id":"resp_f1",',
    '"status":"failed","error":{"code":"server_error",',
    '"message":"The model failed to generate a response."}}}'
  ))
)
write_case(
  o, "failed", o_failed,
  list(e_start("resp_f1"), e_open("text", 1L), e_delta("text", 1L, "Partial"),
       e_error("overloaded", 503L)),
  g_msg("error", err = "server_error: The model failed to generate a response.",
        rid = "resp_f1", content = list(g_text("Partial")))
)

o_incomplete = c(
  ev("response.created", js(
    '{"type":"response.created","response":{"id":"resp_i1",',
    '"status":"in_progress","model":"fixture-1","output":[]}}'
  )),
  ev("response.output_item.added", js(
    '{"type":"response.output_item.added","output_index":0,',
    '"item":{"id":"msg_i1","type":"message","role":"assistant",',
    '"content":[]}}'
  )),
  ev("response.output_text.delta", js(
    '{"type":"response.output_text.delta","output_index":0,',
    '"content_index":0,"delta":"Long answer"}'
  )),
  ev("response.output_item.done", js(
    '{"type":"response.output_item.done","output_index":0,',
    '"item":{"id":"msg_i1","type":"message","role":"assistant",',
    '"status":"incomplete","content":[{"type":"output_text",',
    '"text":"Long answer","annotations":[]}]}}'
  )),
  ev("response.incomplete", js(
    '{"type":"response.incomplete","response":{"id":"resp_i1",',
    '"status":"incomplete","incomplete_details":{"reason":"max_output_tok',
    'ens"},"model":"fixture-1","output":[{"id":"msg_i1","type":"message",',
    '"role":"assistant","status":"incomplete",',
    '"content":[{"type":"output_text","text":"Long answer",',
    '"annotations":[]}]}],"usage":{"input_tokens":50,',
    '"input_tokens_details":{"cached_tokens":0},"output_tokens":16}}}'
  ))
)
i1_sig = '{"v":1,"id":"msg_i1"}'
write_case(
  o, "incomplete", o_incomplete,
  list(e_start("resp_i1"), e_open("text", 1L), e_delta("text", 1L, "Long answer"),
       e_end("text", 1L, g_text("Long answer", i1_sig)), e_done("length")),
  g_msg("length", "incomplete.max_output_tokens", rid = "resp_i1",
        content = list(g_text("Long answer", i1_sig)), usage = g_usage(50, 16))
)

o_cut = c(
  ev("response.created", js(
    '{"type":"response.created","response":{"id":"resp_t1",',
    '"status":"in_progress","model":"fixture-1","output":[]}}'
  )),
  ev("response.output_item.added", js(
    '{"type":"response.output_item.added","output_index":0,',
    '"item":{"id":"fc_t1","type":"function_call","call_id":"call_t1",',
    '"name":"read","arguments":""}}'
  )),
  ev("response.function_call_arguments.delta", js(
    '{"type":"response.function_call_arguments.delta","output_index":0,',
    '"delta":"{\\"path\\":"}'
  ))
)
write_case(
  o, "truncated", o_cut,
  list(e_start("resp_t1"), e_tstart(1L, "call_t1|fc_t1", "read"),
       e_delta("toolcall", 1L, "{\"path\":"), e_error("network")),
  g_msg("error", err = "The Responses stream ended before a terminal response event.",
        rid = "resp_t1",
        content = list(g_tool("call_t1|fc_t1", "read", obj(), raw = "{\"path\":")))
)
```

Run it again:

```bash
Rscript --vanilla tests/testthat/fixtures/sse/make_fixtures.R
ls tests/testthat/fixtures/sse/openai-responses | wc -l
```

Expected: the count is `15` (five cases with three files each).

Create `tests/testthat/test-provider-openai-responses.R`:

```r
# Tests for R/provider-openai-responses.R (plan P12): the openai-responses normaliser and
# request body.
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

api = "openai-responses"

# ---- the normaliser (Task 6) -------------------------------------------------------------------

test_that("responses fixtures give the golden events and final messages (INFRA-02)", {
  expect_all_golden(api, responses_normaliser)
})

test_that("responses events do not depend on how the bytes are chunked (INFRA-23)", {
  for (case in c("reasoning_tools", "backfill", "truncated")) {
    expect_chunk_invariant(api, responses_normaliser, case)
  }
})

test_that("reasoning items, phase and fc_/call_ ids are kept verbatim (INFRA-07)", {
  msg = replay_case(api, responses_normaliser, "reasoning_tools")$message
  types = vapply(msg$content, function(b) b$type, "")
  expect_identical(types, c("thinking", "opaque", "text", "tool_call"))
  item = json_decode(msg$content[[2L]]$json)
  expect_identical(item$encrypted_content, "gAAAAB-fixture-opaque-blob==")
  expect_identical(msg$content[[2L]]$api, api)
  expect_identical(json_decode(msg$content[[3L]]$signature)$phase, "commentary")
  expect_identical(msg$content[[4L]]$id, "call_fixture1|fc_fixture1")
})

test_that("encrypted_content missing from output_item.done is backfilled from completed", {
  msg = replay_case(api, responses_normaliser, "backfill")$message
  item = json_decode(msg$content[[2L]]$json)
  expect_identical(item$encrypted_content, "gAAAAB-backfilled==")
})

test_that("failed and truncated streams each end with one error event and the partial", {
  for (case in c("failed", "truncated")) {
    ev = replay_case(api, responses_normaliser, case)$events
    expect_one_terminal(ev)
    expect_identical(ev[[length(ev)]]$type, "error")
  }
  inc = replay_case(api, responses_normaliser, "incomplete")$message
  expect_identical(inc$stop_reason, "length")
})

test_that("an error event before any delta asks the transport to retry", {
  log = event_log()
  retried = event_log()
  n = responses_normaliser(test_model(api), list(emit = log$emit, retry = retried$emit))
  expect_false(n$push(list(event = "error", data = paste0(
    '{"type":"error","code":"server_is_overloaded","message":"busy"}'
  ))))
  expect_identical(retried$events[[1L]]$class, "overloaded")
  expect_length(log$events, 0L)
  n$finish()
  expect_identical(types_of(log$events), c("start", "error"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-openai-responses")'`
Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 1 ]`, with errors such as ``object 'responses_normaliser' not found``.

- [ ] **Step 3: Write the implementation**

Create `R/provider-openai-responses.R`:

```r
# The openai-responses adapter (P12): the stateless Responses API with store = false. Reasoning
# items (with encrypted_content), message ids with `phase`, and `call_|fc_` ids are replayed
# byte for byte to the same model only (report 08 sections 2.A, 3.1-3.3; verification log rows
# 32 (backfill encrypted_content from response.completed), 37 (keep `phase`) and 40 (a unique
# X-Client-Request-Id per request)). The normaliser is adapted from the verified prototypes of
# report 08 section 5.7 and report 03 section 5.3.

#' A Responses error code -> class suffix, status and retryability (08 sections 2.D, 3.5)
#' @noRd
responses_error_info = function(code) {
  code = code %||% ""
  if (grepl("spend_limit|usage_limit|credit_balance|insufficient_quota", code)) {
    return(list(class = "spend_cap", status = 429L, retry = FALSE))
  }
  if (code %in% c("rate_limit_exceeded", "slow_down")) {
    return(list(class = "rate_limit", status = 429L, retry = TRUE))
  }
  if (code %in% c("server_error", "server_is_overloaded", "overloaded")) {
    return(list(class = "overloaded", status = 503L, retry = TRUE))
  }
  list(class = "provider", status = NA_integer_, retry = FALSE)
}

#' The replay form of a reasoning item: only the fields accepted as input (08 section 3.2)
#' @noRd
responses_reasoning_item = function(item) {
  keep = c("type", "id", "summary", "encrypted_content", "content")
  item[intersect(keep, names(item))]
}

#' The openai-responses normaliser (04 section 8.1; 08 section 3.3)
#'
#' A reasoning item opens two slots: a thinking block with the summary text, and an opaque
#' block holding the reasoning item for replay. A message item's id and `phase` are kept as
#' the text block's signature `{"v":1,"id":...,"phase":...}` (Pi's textSignature).
#' @noRd
responses_normaliser = function(model, opts) {
  st = adp_state(model, opts)
  slots = new.env(parent = emptyenv())

  open_item = function(oi, item) {
    key = as.character(oi)
    if (!is.null(slots[[key]])) return(slots[[key]])
    type = item$type %||% ""
    if (type == "reasoning") {
      i = adp_open(st, "thinking")
      adp_open(st, "opaque")
    } else if (type == "message") {
      i = adp_open(st, "text")
    } else if (type == "function_call") {
      i = adp_open(st, "tool_call", id = paste0(item$call_id, "|", item$id), name = item$name,
                   pj = partial_json())
      adp_delta(st, i, item$arguments)
    } else {
      i = adp_open(st, "opaque")
    }
    assign(key, i, envir = slots)
    i
  }

  slot_of = function(e, kind) {
    i = slots[[as.character(e$output_index)]]
    if (is.null(i) || st$blocks[[i]]$type != kind || st$blocks[[i]]$done) return(NULL)
    i
  }

  finish_item = function(oi, item) {
    i = open_item(oi, item)
    b = st$blocks[[i]]
    type = item$type %||% ""
    if (type == "reasoning") {
      texts = vapply(item$summary %||% list(), function(x) x$text %||% "", "")
      if (!length(texts)) texts = vapply(item$content %||% list(), function(x) x$text %||% "", "")
      b$text_override = paste(texts, collapse = "\n\n")
      adp_close(st, i)
      o = st$blocks[[i + 1L]]
      o$item = item
      adp_set_opaque(st, i + 1L, json_encode(responses_reasoning_item(item)))
    } else if (type == "message") {
      parts = vapply(item$content %||% list(), function(x) {
        if (identical(x$type, "output_text")) x$text %||% "" else x$refusal %||% ""
      }, "")
      b$text_override = paste(parts, collapse = "")
      sig = list(v = 1L, id = item$id)
      if (!is.null(item$phase)) sig$phase = item$phase
      b$signature = json_encode(sig)
      adp_close(st, i)
    } else if (type == "function_call") {
      if (!is.null(item$arguments)) b$raw_override = item$arguments
      adp_close(st, i)
    } else if (b$type == "opaque" && !b$done) {
      adp_set_opaque(st, i, json_encode(item))
    }
    invisible(i)
  }

  on_terminal = function(r) {
    if (!is.null(r$id)) st$response_id = r$id
    u = r[["usage"]]
    if (!is.null(u)) {
      details = u[["input_tokens_details"]]
      cached = details[["cached_tokens"]] %||% 0
      cwrite = details[["cache_write_tokens"]] %||% 0
      st$usage = list(input = max(0, (u[["input_tokens"]] %||% 0) - cached - cwrite),
                      output = u[["output_tokens"]] %||% 0, cache_read = cached,
                      cache_write_5m = cwrite,
                      reasoning = u[["output_tokens_details"]][["reasoning_tokens"]] %||% 0)
    }
    outs = r$output %||% list()
    for (k in seq_along(outs)) {
      item = outs[[k]]
      i = slots[[as.character(k - 1L)]]
      if (is.null(i) || !st$blocks[[i]]$done) {
        finish_item(k - 1L, item)
      } else if (identical(item$type, "reasoning") && !is.null(item$encrypted_content)) {
        o = st$blocks[[i + 1L]]
        if (is.null(o$item$encrypted_content)) {
          o$item$encrypted_content = item$encrypted_content
          adp_set_opaque(st, i + 1L, json_encode(responses_reasoning_item(o$item)))
        }
      }
    }
    status = r$status %||% ""
    reason = r$incomplete_details$reason
    st$raw_stop = if (!is.null(reason)) paste0(status, ".", reason) else status
    if (status == "completed") {
      st$stop_reason = "stop"
    } else if (status == "incomplete" && identical(reason, "max_output_tokens")) {
      st$stop_reason = "length"
    } else {
      st$stop_reason = "error"
      st$error_message = paste0("Response ", status, ": ", reason %||% "no reason given")
    }
    has_tool = any(vapply(st$blocks, function(b) identical(b$type, "tool_call"), logical(1)))
    if (identical(st$stop_reason, "stop") && has_tool) st$stop_reason = "tool_use"
    adp_done(st)
    TRUE
  }

  push = function(ev) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    data = ev$data %||% ""
    if (!nzchar(data) || identical(trimws(data), "[DONE]")) return(FALSE)
    e = adp_json_try(data)
    if (!adp_is_object(e)) {
      adp_error(st, paste0("Could not parse a Responses stream event: ", substr(data, 1L, 200L)))
      return(TRUE)
    }
    type = e$type %||% ""
    if (type %in% c("response.created", "response.in_progress", "response.queued")) {
      st$response_id = e$response$id %||% st$response_id
      rm = e$response$model
      if (!is.null(rm) && !identical(rm, model$id)) st$response_model = rm
    } else if (type == "response.output_item.added") {
      open_item(e$output_index, e$item)
    } else if (type == "response.reasoning_summary_part.added") {
      i = slot_of(e, "thinking")
      if (!is.null(i) && (e$summary_index %||% 0L) > 0L) adp_delta(st, i, "\n\n")
    } else if (type %in% c("response.reasoning_summary_text.delta",
                           "response.reasoning_text.delta")) {
      i = slot_of(e, "thinking")
      if (!is.null(i)) adp_delta(st, i, e$delta)
    } else if (type %in% c("response.output_text.delta", "response.refusal.delta")) {
      i = slot_of(e, "text")
      if (!is.null(i)) adp_delta(st, i, e$delta)
    } else if (type == "response.function_call_arguments.delta") {
      i = slot_of(e, "tool_call")
      if (!is.null(i)) adp_delta(st, i, e$delta)
    } else if (type == "response.function_call_arguments.done") {
      i = slot_of(e, "tool_call")
      if (!is.null(i)) {
        prev = adp_buffer_text(st$blocks[[i]]$buf)
        full = e$arguments %||% prev
        if (startsWith(full, prev) && nchar(full) > nchar(prev)) {
          adp_delta(st, i, substr(full, nchar(prev) + 1L, nchar(full)))
        } else if (!identical(full, prev)) {
          st$blocks[[i]]$raw_override = full
        }
      }
    } else if (type == "response.output_item.done") {
      finish_item(e$output_index, e$item)
    } else if (type %in% c("response.completed", "response.incomplete")) {
      return(on_terminal(e$response))
    } else if (type == "response.failed") {
      err = e$response$error
      info = responses_error_info(err$code)
      msg = paste0(err$code %||% "unknown", ": ", err$message %||% "no message")
      return(adp_stream_error(st, opts, msg, class = info$class, status = info$status,
                              retryable = info$retry))
    } else if (type == "error") {
      code = e$code %||% e$error$code
      info = responses_error_info(code)
      msg = paste0(code %||% "error", ": ", e$message %||% e$error$message %||% "unknown error")
      return(adp_stream_error(st, opts, msg, class = info$class, status = info$status,
                              retryable = info$retry))
    }
    FALSE
  }

  finish = function() {
    if (st$terminal) return(st$final)
    if (!is.null(st$pending)) return(adp_finish_pending(st))
    adp_error(st, "The Responses stream ended before a terminal response event.",
              class = "network")
  }

  adp_normaliser(st, push, finish)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-openai-responses")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 49 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-openai-responses.R tests/testthat/test-provider-openai-responses.R tests/testthat/fixtures/sse/make_fixtures.R tests/testthat/fixtures/sse/openai-responses
git commit -m "feat(provider): add the openai-responses normaliser"
```

---

### Task 7: Responses request bodies and `builtin:openai`

**Files:**
- Modify: `R/provider-openai-responses.R` (append)
- Modify: `tests/testthat/fixtures/sse/replay_helpers.R` (append)
- Test: `tests/testthat/test-provider-openai-responses.R` (append)

**Interfaces:**
- Consumes: the Task 2 request helpers, `compat_flags()` (Task 4; its `explicit_cache_mode` is `TRUE` for the provider `openai`), `gptr_adapter()`, `ext_declare_builtin()`, `on_load()`, `json_encode()`, `json_obj()`, `json_verbatim()`, `hash_xxh128()` (P01/P02); tests as in Task 2, plus P05's `project_messages()` and P01's `schema_validate()` for the INFRA-08 hand-off test.
- Produces: `responses_build(model, context, opts)`, `responses_caps()`, `responses_image()`, `responses_user()`, `responses_assistant()`, `responses_tool_result()`, `responses_tools()`, `responses_operator()`, `responses_tool_choice()`, `builtin_openai(gptr)` and the registered adapter `openai-responses`. Test helpers (in `replay_helpers.R`): `handoff_entries(more = list())` (an Anthropic-origin transcript and its opaque strings), `wire_object()` and `responses_body_schema()` (the Responses schema fixture of INFRA-08).

Body rules (report 08 sections 2.A, 3.1-3.2 and verification rows 34-40; G4 sections 2.4, 3.7): key order `model`, `store: false`, `stream`, `prompt_cache_key` (the plan's key, at most 64 characters), `prompt_cache_options: {mode: "implicit"}` (OpenAI itself, GPT-5.6 and later), `reasoning` (`effort`, `summary: "auto"`; `effort: "none"` for `off` where the model allows it) with `include: ["reasoning.encrypted_content"]`, `max_output_tokens` (at least 16), `tool_choice` (`"none"`, `"required"` or `{type: "function", name}` when forced choice is allowed and `returns` is not set), the declared request params, `tools` (flat function tools with `strict: false`, converted once per session), `input` last. `input[0]` is a developer message holding T0 and T1 as `input_text` parts with `prompt_cache_breakpoint: {mode: "explicit"}` on the anchors the plan names, and the anchored project block carries one too. For the same model, opaque reasoning items replay verbatim, text replays as a `message` item with its `id` and `phase`, and calls keep their `fc_` id; other models get plain assistant text and `call_` ids only. Tool results are `function_call_output` items whose output is a string or, with images, `input_text` and `input_image` parts (acceptance 3). Operator messages are developer messages, with their tool declarations as an `additional_tools` item; `returns` adds a developer instruction at the tail. Every request carries `x-client-request-id` = the context's `request_id` ("must be unique per request", verification row 40).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/fixtures/sse/replay_helpers.R`:

```r
# A Responses stream with one function call
responses_sse_tool = function(call_id, name, json) {
  item = paste0('{"id":"fc_w1","type":"function_call","status":"completed","call_id":"', call_id,
                '","name":"', name, '","arguments":', json_encode(json), "}")
  paste0(
    sse_event("response.created", paste0('{"type":"response.created","response":',
                                         '{"id":"resp_w1","status":"in_progress",',
                                         '"output":[]}}')),
    sse_event("response.output_item.added", paste0('{"type":"response.output_item.added",',
                                                   '"output_index":0,"item":', item, "}")),
    sse_event("response.output_item.done", paste0('{"type":"response.output_item.done",',
                                                  '"output_index":0,"item":', item, "}")),
    sse_event("response.completed", paste0('{"type":"response.completed","response":',
                                           '{"id":"resp_w1","status":"completed","output":[',
                                           item, '],"usage":{"input_tokens":20,',
                                           '"output_tokens":5}}}'))
  )
}

# A Responses stream with one assistant message
responses_sse_text = function(text) {
  item = paste0('{"id":"msg_w2","type":"message","role":"assistant","status":"completed",',
                '"phase":"final_answer","content":[{"type":"output_text","text":',
                json_encode(text), ',"annotations":[]}]}')
  paste0(
    sse_event("response.created", paste0('{"type":"response.created","response":',
                                         '{"id":"resp_w2","status":"in_progress",',
                                         '"output":[]}}')),
    sse_event("response.output_item.added", paste0('{"type":"response.output_item.added",',
                                                   '"output_index":0,"item":', item, "}")),
    sse_event("response.output_item.done", paste0('{"type":"response.output_item.done",',
                                                  '"output_index":0,"item":', item, "}")),
    sse_event("response.completed", paste0('{"type":"response.completed","response":',
                                           '{"id":"resp_w2","status":"completed","output":[',
                                           item, '],"usage":{"input_tokens":30,',
                                           '"output_tokens":6}}}'))
  )
}

# ---- INFRA-08 body leg (03 section 6.18 row 08): an Anthropic-origin transcript ----------------

# Transcript entries (04 section 4.6 shape, as P06 stores them) of a conversation built on
# Anthropic: the thinking_tools fixture turn (signed and redacted thinking, two parallel tool
# calls) with its two results, then the messages of `more`. `opaque` holds every opaque string of
# the assistant messages (signatures, redacted data, reasoning items and their encrypted content,
# thought signatures), none of which a foreign target may receive
handoff_entries = function(more = list()) {
  turn = replay_case("anthropic-messages", anthropic_normaliser, "thinking_tools")$message
  msgs = c(list(first_message(), turn,
                msg_tool_result("toolu_01A", "r", "[1] 26.7 19.7 15.1", timestamp = 3),
                msg_tool_result("toolu_01B", "read", "x = 1", timestamp = 4)), more)
  entries = list()
  opaque = character()
  for (k in seq_along(msgs)) {
    entries[[k]] = list(type = "message", id = paste0("e", k),
                        parent_id = if (k > 1L) paste0("e", k - 1L),
                        timestamp = "2026-10-01T10:00:00.000Z", message = msgs[[k]])
    if (!identical(msgs[[k]][["role"]], "assistant")) next
    for (b in msgs[[k]][["content"]]) {
      opaque = c(opaque, b[["signature"]], b[["data"]], b[["thought_signature"]])
      if (identical(b[["type"]], "opaque")) {
        opaque = c(opaque, b[["json"]], json_decode(b[["json"]])[["encrypted_content"]])
      }
    }
  }
  list(entries = entries, leaf = paste0("e", length(msgs)),
       opaque = unique(opaque[nzchar(opaque)]))
}

# A closed object schema for P01's schema_validate(): unknown keys are errors
wire_object = function(properties, required = NULL) {
  s = list(type = "object", properties = properties, additionalProperties = FALSE)
  if (length(required)) s$required = required
  s
}

# The schema fixture of a Responses request body (report 08 section 3.1; G4 section 3.7): the
# fields and input items gptr sends, closed, so a foreign key such as a signature fails
responses_body_schema = function() {
  str = list(type = "string")
  arr = list(type = "array")
  enum = function(...) list(type = "string", enum = c(...))
  breakpoint = wire_object(list(mode = enum("explicit")))
  part = wire_object(list(type = enum("input_text", "input_image", "output_text"), text = str,
                          detail = str, image_url = str, annotations = arr,
                          prompt_cache_breakpoint = breakpoint), "type")
  content = list(type = c("string", "array"), items = part)
  item = wire_object(list(type = enum("message", "reasoning", "function_call",
                                      "function_call_output", "additional_tools"),
                          role = enum("developer", "user", "assistant"), id = str, status = str,
                          phase = str, content = content, summary = arr,
                          encrypted_content = str, call_id = str, name = str, arguments = str,
                          output = content, tools = arr))
  tool = wire_object(list(type = str, name = str, description = str,
                          parameters = list(type = "object"), strict = list(type = "boolean")),
                     c("type", "name", "parameters"))
  top = list(model = str, store = list(type = "boolean", enum = FALSE),
             stream = list(type = "boolean"), prompt_cache_key = str,
             prompt_cache_options = wire_object(list(mode = str)),
             reasoning = wire_object(list(effort = str, summary = str)),
             include = list(type = "array", items = str),
             max_output_tokens = list(type = "integer"),
             tool_choice = list(type = c("string", "object")),
             tools = list(type = "array", items = tool), service_tier = str,
             metadata = list(type = "object"), safety_identifier = str,
             input = list(type = "array", items = item))
  wire_object(top, c("model", "store", "stream", "input"))
}
```

Append to `tests/testthat/test-provider-openai-responses.R`:

```r
# ---- the request body and the built-in (Task 7) ------------------------------------------------

test_that("Responses bodies: store = false, the cache key, explicit breakpoints (G4 3.7)", {
  model = test_model(api, provider = "openai", id = "gpt-6-sol")
  plan = list(anchors = c("t0", "t1", "project"), tail_ttl = "5m", key = "gptr:0123456789ab")
  req = responses_build(model, ctx_fixture(list(first_message()), cache_plan = plan),
                        list(base_url = "https://api.openai.com/v1"))
  body = json_decode(req$body)
  expect_identical(names(body)[1:5], c("model", "store", "stream", "prompt_cache_key",
                                       "prompt_cache_options"))
  expect_identical(names(body)[length(body)], "input")
  expect_false(body$store)
  expect_identical(body$prompt_cache_key, "gptr:0123456789ab")
  expect_equal(body$prompt_cache_options, list(mode = "implicit"))
  dev = body$input[[1L]]
  expect_identical(dev$role, "developer")
  expect_equal(dev$content[[1L]]$prompt_cache_breakpoint, list(mode = "explicit"))
  expect_equal(dev$content[[2L]]$prompt_cache_breakpoint, list(mode = "explicit"))
  user = body$input[[2L]]$content
  expect_equal(user[[1L]]$prompt_cache_breakpoint, list(mode = "explicit"))
  expect_null(user[[2L]]$prompt_cache_breakpoint)
  read_params = list(type = "object", required = list("path"),
                     properties = list(path = list(type = "string")))
  expect_identical(body$tools[[1L]], list(type = "function", name = "read",
                                          description = "Read a file.",
                                          parameters = read_params, strict = FALSE))
  expect_identical(req$url, "https://api.openai.com/v1/responses")
  expect_identical(req$headers$`x-client-request-id`, "q0123456789ab")
  other = json_decode(responses_build(test_model(api), ctx_fixture(list(first_message())),
                                      list())$body)
  expect_null(other$prompt_cache_options)
  expect_false(grepl("prompt_cache_breakpoint", json_encode(other$input), fixed = TRUE))
})

test_that("the default cache policy gives T0, T1 and project breakpoints (acceptance 4)", {
  plan = default_plan(api)
  expect_identical(plan$anchors, c("t0", "t1", "project"))
  model = test_model(api, provider = "openai", id = "gpt-6-sol")
  req = responses_build(model, ctx_fixture(list(first_message()), cache_plan = plan), list())
  expect_identical(lengths(regmatches(req$body, gregexpr("prompt_cache_breakpoint", req$body))),
                   3L)
  expect_identical(json_decode(req$body)$prompt_cache_key, plan$key)
})

test_that("reasoning items, phase and fc_ ids replay byte for byte to the same model only", {
  dir = sse_dir(api)
  model = adp_fixture_model(api, dir)
  msg = replay_case(api, responses_normaliser, "reasoning_tools")$message
  ctx = ctx_fixture(list(first_message(), msg,
                         msg_tool_result("call_fixture1|fc_fixture1", "r", "[1] 10")))
  req = responses_build(model, ctx, list())
  expect_true(grepl(msg$content[[2L]]$json, req$body, fixed = TRUE))
  items = json_decode(req$body)$input
  kinds = vapply(items, function(x) x$type %||% x$role, "")
  expect_identical(kinds, c("developer", "user", "reasoning", "message", "function_call",
                            "function_call_output"))
  expect_identical(items[[4L]]$phase, "commentary")
  expect_identical(items[[4L]]$id, "msg_fixture1")
  expect_identical(items[[5L]]$id, "fc_fixture1")
  expect_identical(items[[5L]]$call_id, "call_fixture1")
  expect_identical(items[[6L]]$call_id, "call_fixture1")
  other = json_decode(responses_build(test_model(api, id = "other-1"), ctx, list())$body)$input
  kinds = vapply(other, function(x) x$type %||% x$role, "")
  expect_false("reasoning" %in% kinds)
  fc = other[[which(kinds == "function_call")]]
  expect_null(fc$id)
  expect_identical(fc$call_id, "call_fixture1")
})

test_that("a handed-off Anthropic conversation: no foreign opaque data, valid body (INFRA-08)", {
  model = test_model(api, provider = "openai", id = "gpt-6-sol")
  plan = list(anchors = c("t0", "t1", "project"), tail_ttl = "5m", key = "gptr:0123456789ab")
  h = handoff_entries()
  expect_length(h$opaque, 2L)
  # P05's projection (project_messages() ends with handoff_transform()), as request_build() runs it
  msgs = project_messages(h$entries, h$leaf, model)
  wire = responses_build(model, ctx_fixture(msgs, cache_plan = plan), list())$body
  for (s in h$opaque) expect_false(grepl(s, wire, fixed = TRUE), label = s)
  body = json_decode(wire)
  expect_identical(schema_validate(responses_body_schema(), body)$errors, character())
  expect_identical(names(body)[1:5], c("model", "store", "stream", "prompt_cache_key",
                                       "prompt_cache_options"))
  expect_identical(names(body)[length(body)], "input")
  expect_identical(lengths(regmatches(wire, gregexpr("prompt_cache_breakpoint", wire,
                                                     fixed = TRUE))), 3L)
  kinds = vapply(body$input, function(x) x$type %||% x$role, "")
  expect_identical(kinds, c("developer", "user", "assistant", "assistant", "function_call",
                            "function_call", "function_call_output", "function_call_output"))
  expect_identical(body$input[[3L]]$content,
                   "The user wants mpg by cyl. Aggregate in the session.")
  expect_identical(vapply(body$input[5:8], function(x) x$call_id, ""),
                   c("toolu_01A", "toolu_01B", "toolu_01A", "toolu_01B"))
  expect_null(body$input[[5L]]$id)
  # the schema is closed: an Anthropic signature on an item does not validate
  bad = body
  bad$input[[5L]]$signature = h$opaque[[1L]]
  expect_false(schema_validate(responses_body_schema(), bad)$ok)
})

test_that("a PNG tool result is sent as an input_image (acceptance 3)", {
  model = test_model(api)
  call = block_tool_call("call_9|fc_9", "r", list(code = "plot(1)"))
  asst = msg_assistant(list(call), api = api, provider = model$provider, model = model$id,
                       stop_reason = "tool_use")
  res = msg_tool_result("call_9|fc_9", "r", list(block_text("drawn"), block_image(png_b64())))
  body = json_decode(responses_build(model, ctx_fixture(list(msg_user("plot"), asst, res)),
                                     list())$body)
  out = body$input[[length(body$input)]]
  expect_identical(out$type, "function_call_output")
  expect_identical(out$output[[1L]], list(type = "input_text", text = "drawn"))
  expect_identical(out$output[[2L]]$type, "input_image")
  expect_identical(out$output[[2L]]$image_url, paste0("data:image/png;base64,", png_b64()))
})

test_that("reasoning effort, tool_choice, operators and returns follow 08 section 3.1", {
  model = test_model(api, thinking_levels = c("off", "low", "high"))
  body = json_decode(responses_build(model, ctx_fixture(list(msg_user("x")),
                                                        params = list(thinking = "high")),
                                     list())$body)
  expect_equal(body$reasoning, list(effort = "high", summary = "auto"))
  expect_identical(body$include, list("reasoning.encrypted_content"))
  body = json_decode(responses_build(model, ctx_fixture(list(msg_user("x")),
                                                        params = list(thinking = "off")),
                                     list())$body)
  expect_equal(body$reasoning, list(effort = "none"))
  forced = list(tool_choice = list(type = "tool", name = "read"))
  body = json_decode(responses_build(model, ctx_fixture(list(msg_user("x")), params = forced),
                                     list())$body)
  expect_equal(body$tool_choice, list(type = "function", name = "read"))
  add = msg_operator("tool_change", "New tool: lint.",
                     tool_add = list(list(name = "lint", description = "Lint a file.",
                                          input_schema = list(type = "object"))))
  items = json_decode(responses_build(model, ctx_fixture(list(msg_user("x"), add)),
                                      list())$body)$input
  expect_identical(items[[3L]], list(role = "developer", content = "New tool: lint."))
  expect_identical(items[[4L]]$type, "additional_tools")
  expect_identical(items[[4L]]$tools[[1L]]$name, "lint")
  body = json_decode(responses_build(model, ctx_fixture(list(msg_user("x")),
                                                        params = list(returns = count_schema())),
                                     list())$body)
  last = body$input[[length(body$input)]]
  expect_identical(last$role, "developer")
  expect_match(last$content, "JSON Schema", fixed = TRUE)
  expect_null(body$text)
})

test_that("the frozen prefix stays byte-identical across turns (acceptance 4)", {
  model = test_model(api, provider = "openai", id = "gpt-6-sol")
  plan = list(anchors = c("t0", "t1", "project"), tail_ttl = "5m", key = "gptr:0123456789ab")
  call = block_tool_call("call_A1|fc_A1", "r", list(code = "nrow(d)"))
  asst = msg_assistant(list(block_text("Checking."), call), api = api, provider = "openai",
                       model = "gpt-6-sol", stop_reason = "tool_use", timestamp = 2)
  turn2 = list(first_message(), asst, msg_tool_result("call_A1|fc_A1", "r", "[1] 32"))
  memo = new.env(parent = emptyenv())
  b1 = responses_build(model, ctx_fixture(list(first_message()), cache_plan = plan),
                       list(memo = memo))$body
  b2 = responses_build(model, ctx_fixture(turn2, cache_plan = plan), list(memo = memo))$body
  expect_true(startsWith(b2, substr(b1, 1L, nchar(b1) - 2L)))
  expect_identical(b2, responses_build(model, ctx_fixture(turn2, cache_plan = plan), list())$body)
})

test_that("builtin:openai registers the adapter; check_adapter() and gptr_check() pass", {
  a = adapter_get(api)
  expect_identical(a$capabilities$operator_role, "developer")
  expect_true(a$capabilities$tool_addition)
  res = check_adapter(a, fixtures = sse_dir(api))
  expect_true(all(res$ok), label = paste(res$check[!res$ok], collapse = "; "))
  expect_true("adapter.reasoning_tools.roundtrip" %in% res$check)
  expect_true(all(gptr_check(a)$ok))
})

test_that("returns = through the run loop on Responses: instruction and validation (INFRA-25)", {
  local_gptr_options(unsafe_no_permissions = TRUE)
  local_scripted_provider(api)
  local_count_tool()
  wire = local_scripted_wire(list(responses_sse_tool("call_w1", "count", "{}"),
                                  responses_sse_text("{\"n\":32}")))
  s = session_new("scripted/scripted-1", "auto", home = new.env())
  session_run(s, msg_user("How many rows?"), list(returns = count_schema()))
  expect_identical(s$value$n, 32L)
  expect_identical(vapply(s$messages, function(m) m$role, ""),
                   c("user", "assistant", "tool_result", "assistant"))
  expect_match(wire$requests[[2L]]$url, "/responses$")
  # the run's returns schema reaches the wire as the closing developer instruction (IC-71)
  first = json_decode(wire$requests[[1L]]$body)
  closing = first$input[[length(first$input)]]
  expect_identical(closing$role, "developer")
  expect_match(closing$content, "JSON Schema", fixed = TRUE)
  expect_null(first$tool_choice)
  second = json_decode(wire$requests[[2L]]$body)$input
  kinds = vapply(second, function(x) x$type %||% x$role, "")
  expect_true(all(c("function_call", "function_call_output") %in% kinds))
})

test_that("end to end on the mock server: a Responses stream (skip on CRAN)", {
  skip_on_cran()
  srv = local_mock_server("openai_responses", n = 3L, interval = 0.02)
  r = mock_stream(srv)
  expect_identical(r$types, c("start", "text_start", rep("text_delta", 3L), "text_end", "done"))
  expect_identical(msg_text(r$message), "tok01 tok02 tok03 ")
  expect_identical(r$message$response_id, "resp_mock")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-openai-responses")'`
Expected: `[ FAIL 12 | WARN 0 | SKIP 0 | PASS 50 ]`, with errors such as ``could not find function "responses_build"`` and `No adapter is registered for the api openai-responses.`

- [ ] **Step 3: Write the implementation**

Append to `R/provider-openai-responses.R`:

```r
#' Adapter capabilities of openai-responses (04 section 8.1; IC-69, IC-71)
#' @noRd
responses_caps = function() {
  list(images_in_results = TRUE, tool_addition = TRUE, structured_output = FALSE,
       reasoning_replay = TRUE, parallel_tools = TRUE, forced_tool_choice = TRUE,
       request_params = c("service_tier", "metadata", "safety_identifier"),
       operator_role = "developer", cache = "openai", max_tool_name = 64L,
       tool_shape = "responses")
}

#' A Responses input_image part (data URL), or an input_text note for a text-only model
#' @noRd
responses_image = function(b, images) {
  if (!images) return(list(type = "input_text", text = adp_image_note()))
  list(type = "input_image", detail = "auto",
       image_url = paste0("data:", b$mime, ";base64,", b$data))
}

#' The input items of a user message; the anchored project block carries an explicit
#' breakpoint when the cache plan names it (G4 section 3.7)
#' @noRd
responses_user = function(m, mark_anchor, images) {
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    if (type %in% c("text", "context") && nzchar(b$text)) {
      p = list(type = "input_text", text = b$text)
      if (mark_anchor && type == "context" && isTRUE(b$anchor)) {
        p$prompt_cache_breakpoint = list(mode = "explicit")
      }
      parts[[length(parts) + 1L]] = p
    } else if (type == "image") {
      parts[[length(parts) + 1L]] = responses_image(b, images)
    }
  }
  if (!length(parts)) return(list())
  list(list(role = "user", content = parts))
}

#' The input items of an assistant message: reasoning items, message ids with `phase` and
#' `fc_` ids only for the same model; other models get plain text and call ids (Pi 296-306)
#' @noRd
responses_assistant = function(m, model) {
  same = adp_same_model(m, model)
  items = list()
  for (b in m$content) {
    type = b$type %||% ""
    it = NULL
    if (type == "opaque") {
      if (same) it = json_verbatim(b$json)
    } else if (type == "thinking") {
      if (!same && nzchar(trimws(b$thinking))) it = list(role = "assistant", content = b$thinking)
    } else if (type == "text") {
      if (nzchar(b$text)) {
        sig = if (same) adp_json_try(b$signature %||% "") else NULL
        if (is.character(sig$id)) {
          it = list(type = "message", role = "assistant", id = sig$id)
          if (!is.null(sig$phase)) it$phase = sig$phase
          it$status = "completed"
          it$content = list(list(type = "output_text", text = b$text, annotations = list()))
        } else {
          it = list(role = "assistant", content = b$text)
        }
      }
    } else if (type == "tool_call") {
      ids = strsplit(b$id, "|", fixed = TRUE)[[1L]]
      it = list(type = "function_call")
      if (same && length(ids) > 1L && startsWith(ids[[2L]], "fc_")) it$id = ids[[2L]]
      it$call_id = ids[[1L]]
      it$name = b$name
      it$arguments = json_encode(if (length(b$arguments)) b$arguments else json_obj())
    }
    if (!is.null(it)) items[[length(items) + 1L]] = it
  }
  items
}

#' The function_call_output item of a tool result (images as input_image parts, acceptance 3)
#' @noRd
responses_tool_result = function(r, images) {
  texts = character()
  imgs = list()
  for (b in r$content) {
    if (identical(b$type, "text")) texts = c(texts, b$text)
    if (identical(b$type, "image")) imgs[[length(imgs) + 1L]] = responses_image(b, images)
  }
  txt = paste(texts, collapse = "\n")
  call_id = strsplit(r$tool_call_id, "|", fixed = TRUE)[[1L]][[1L]]
  output = if (!length(imgs)) {
    if (nzchar(txt)) txt else "(no tool output)"
  } else {
    c(if (nzchar(txt)) list(list(type = "input_text", text = txt)), imgs)
  }
  list(list(type = "function_call_output", call_id = call_id, output = output))
}

#' Responses function tools from the frozen Anthropic-shape array (flat, strict = FALSE)
#' @noRd
responses_tools = function(tools) {
  lapply(tools, function(t) {
    list(type = "function", name = t$name, description = t$description %||% "",
         parameters = t$input_schema, strict = FALSE)
  })
}

#' The input items of an operator message: a developer message and an additional_tools item
#' @noRd
responses_operator = function(m, with_tools) {
  items = list()
  text = adp_operator_text(m)
  if (nzchar(text)) items[[1L]] = list(role = "developer", content = text)
  if (with_tools && length(m$tool_add)) {
    defs = lapply(m$tool_add, function(t) {
      list(name = t$name, description = t$description, input_schema = t$input_schema)
    })
    items[[length(items) + 1L]] = list(type = "additional_tools", role = "developer",
                                       tools = responses_tools(defs))
  }
  items
}

#' The tool_choice field of a Responses request, or NULL for the default `auto`
#' @noRd
responses_tool_choice = function(tc, model, returns) {
  if (identical(tc, "none")) return("none")
  if (!adp_forced(tc) || !adp_forced_ok(model, responses_caps()) || !is.null(returns)) {
    return(NULL)
  }
  if (identical(tc$type, "any")) "required" else list(type = "function", name = tc$name)
}

#' build() of the openai-responses adapter (04 section 8.1; G4 section 3.7: model, store,
#' stream, prompt_cache_key, prompt_cache_options, reasoning, tools, input)
#' @noRd
responses_build = function(model, context, opts) {
  params = context$params %||% list()
  plan = adp_cache_plan(context)
  anchors = plan$anchors %||% character()
  compat = compat_flags(model$provider, model)
  explicit = isTRUE(compat$explicit_cache_mode)
  images = adp_images_ok(model)
  add_tools = isTRUE(adp_model_cap(model, "tool_addition", TRUE))
  msgs = context$messages %||% list()
  anchor_at = adp_anchor_index(msgs)

  head = list(model = model$id, store = FALSE, stream = TRUE)
  if (!is.null(plan$key) && nzchar(plan$key)) head$prompt_cache_key = substr(plan$key, 1L, 64L)
  if (explicit) head$prompt_cache_options = list(mode = "implicit")
  if (isTRUE(model$reasoning)) {
    level = params$thinking
    if (identical(level, "off")) {
      if ("off" %in% unlist(model$thinking_levels)) head$reasoning = list(effort = "none")
    } else {
      r = list()
      eff = params$effort %||% level
      if (!is.null(eff)) r$effort = eff
      r$summary = "auto"
      head$reasoning = r
      head$include = list("reasoning.encrypted_content")
    }
  }
  if (!is.null(params$max_tokens)) head$max_output_tokens = max(16L, as.integer(params$max_tokens))
  if (!is.null(params$temperature) && !isTRUE(model$reasoning)) {
    head$temperature = params$temperature
  }
  tc = responses_tool_choice(params$tool_choice, model, params$returns)
  if (!is.null(tc)) head$tool_choice = tc
  for (f in responses_caps()$request_params) if (!is.null(params[[f]])) head[[f]] = params[[f]]

  extra = character()
  tj = adp_tools_json(opts, "openai-responses", context$tools_json, responses_tools)
  if (!is.null(tj)) extra = c(extra, paste0("\"tools\":", tj))

  elements = character()
  sys = list()
  for (k in c("t0", "t1")) {
    txt = context$system[[k]] %||% ""
    if (!nzchar(txt)) next
    p = list(type = "input_text", text = txt)
    if (explicit && k %in% anchors) p$prompt_cache_breakpoint = list(mode = "explicit")
    sys[[length(sys) + 1L]] = p
  }
  if (length(sys)) {
    key = paste("openai-responses", "system", hash_xxh128(sys), sep = "|")
    elements = c(elements, adp_memo(opts, key, function() {
      json_encode(list(role = "developer", content = sys))
    }))
  }
  mark_project = explicit && "project" %in% anchors
  for (k in seq_along(msgs)) {
    m = msgs[[k]]
    role = m$role %||% ""
    same = adp_same_model(m, model)
    mark = mark_project && identical(k, anchor_at)
    key = paste("openai-responses", role, adp_msg_key(m), same, mark, images, add_tools,
                sep = "|")
    el = adp_memo(opts, key, function() {
      items = switch(role,
                     user = responses_user(m, mark, images),
                     assistant = responses_assistant(m, model),
                     tool_result = responses_tool_result(m, images),
                     operator = responses_operator(m, add_tools),
                     list())
      if (!length(items)) "" else paste(vapply(items, json_encode, ""), collapse = ",")
    })
    if (nzchar(el)) elements = c(elements, el)
  }
  if (!is.null(params$returns)) {
    elements = c(elements, json_encode(list(role = "developer",
                                            content = adp_returns_instruction(params$returns))))
  }

  headers = list(`content-type` = "application/json", accept = "text/event-stream")
  if (!is.null(opts$credential)) {
    headers$authorization = adp_header_secret(opts$credential, "Bearer ")
  }
  if (!is.null(context$request_id)) headers$`x-client-request-id` = context$request_id
  headers = c(headers, adp_provider_headers(model))

  list(url = adp_url(opts$base_url %||% "https://api.openai.com/v1", "responses"),
       method = "POST", headers = headers,
       body = adp_body(head, extra, "input", elements), stream = "sse")
}

#' builtin:openai: registers the openai-responses adapter (04 sections 7.12, 10.3)
#' @noRd
builtin_openai = function(gptr) {
  gptr$register(gptr_adapter("openai-responses", transport = "http_sse",
                             build = responses_build, parse = responses_normaliser,
                             capabilities = responses_caps()))
  invisible(NULL)
}

on_load(ext_declare_builtin("openai", builtin_openai))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-openai-responses")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 120 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-openai-responses.R tests/testthat/test-provider-openai-responses.R tests/testthat/fixtures/sse/replay_helpers.R
git commit -m "feat(provider): build openai-responses request bodies and register builtin:openai"
```

---

### Task 8: Gemini normaliser

**Files:**
- Create: `R/provider-google.R`
- Modify: `tests/testthat/fixtures/sse/make_fixtures.R` (append) and, by running it, `tests/testthat/fixtures/sse/google-generative-ai/` (16 files)
- Test: `tests/testthat/test-provider-google.R` (create)

**Interfaces:**
- Consumes: the Task 1 core (`adp_state()`, `adp_open()`, `adp_delta()`, `adp_close()`, `adp_error()`, `adp_done()`, `adp_stream_error()`, `adp_finish_pending()`, `adp_normaliser()`, `adp_json_try()`, `adp_is_object()`), `json_encode()`, `json_obj()` (P01).
- Produces: `google_normaliser(model, opts)` (the adapter's `parse`), `google_major(id)`, `google_uses_level(id)`, `google_needs_id(id)`, `google_valid_sig(s)`, `google_budget(id, level)`, `google_error_info(err)`.

The normaliser ports Pi's Gemini stream loop (report 09 sections 2.1-2.2, 3.1, 4.5 and verification rows 4-9; `google-generative-ai.ts:106-278`, `google-shared.ts:72-83`): parts with `thought: true` stream as thinking and others as text, a `thoughtSignature` is kept on the exact block its part belongs to (a signature on an empty text part attaches to the open block or opens an empty text block), function calls arrive whole (their arguments are emitted as one delta and the block closes at once) with the signature of the first parallel call kept on that call only, missing or duplicate call ids are generated as `<name>_<response id fragment>_<n>`, usage is `promptTokenCount - cachedContentTokenCount` input, `candidatesTokenCount + thoughtsTokenCount` output, `cachedContentTokenCount` cache reads and `thoughtsTokenCount` reasoning, `STOP` maps to `stop` (`tool_use` with calls) and `MAX_TOKENS` to `length`, and every other finish reason, a blocked prompt (`promptFeedback.blockReason`) or a stream without a finish reason ends in one `error` event with the raw value kept. Error chunks (`RESOURCE_EXHAUSTED`, `UNAVAILABLE`, `INTERNAL`) are retryable before any delta.

Fixtures: `thought_tools` (a signed thought, text, two parallel calls with the signature on the first, usage with cached tokens), `text_signature` (a signature on a final empty text part), `blocked`, `unknown_finish` (`MISSING_THOUGHT_SIGNATURE`), `truncated`; `model.json` makes the fixture model `google/gemini-3.8-flash` so calls and responses carry ids.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/fixtures/sse/make_fixtures.R`:

```r
# ============================================================================================
# google-generative-ai (model.json: a Gemini 3 model, so calls and responses carry ids)
# ============================================================================================
g = "google-generative-ai"
dir.create(file.path(root, g), showWarnings = FALSE, recursive = TRUE)
write_text(file.path(root, g, "model.json"), '{"provider": "google", "id": "gemini-3.8-flash"}\n')
tsig = "CiQBjz1rX3NpZ1RoaW5r"
csig = "CiQBjz1rX3NpZ0NhbGw="
xsig = "Q2lnVGV4dFNpZw=="
stopifnot(nchar(c(tsig, csig, xsig)) %% 4L == 0L)
gem_chunk = function(parts, extra = "") {
  js(
    '{"candidates":[{"content":{"parts":', parts, ',"role":"model"},"index":0', extra,
    '}],"modelVersion":"gemini-3.8-flash","responseId":"k9_XaJ3vGsmWz7IP"}'
  )
}
g_tools = c(
  dat(gem_chunk('[{"text":"**Working out the query**\\n","thought":true}]')),
  dat(gem_chunk(js(
    '[{"text":"I should list files first.","thought":true,"thoughtSignature":"', tsig, '"}]'
  ))),
  dat(gem_chunk('[{"text":"Let me look at "}]')),
  dat(gem_chunk('[{"text":"the directory."}]')),
  dat(js(
    '{"candidates":[{"content":{"parts":[{"functionCall":{"id":"fc_7h2k","name":"find",',
    '"args":{"pattern":"*.R"}},"thoughtSignature":"', csig, '"},',
    '{"functionCall":{"id":"fc_8j3m","name":"read","args":{"path":"R/a.R"}}}],',
    '"role":"model"},"finishReason":"STOP","index":0}],',
    '"usageMetadata":{"promptTokenCount":812,"cachedContentTokenCount":512,',
    '"candidatesTokenCount":31,"thoughtsTokenCount":43,"totalTokenCount":886},',
    '"modelVersion":"gemini-3.8-flash","responseId":"k9_XaJ3vGsmWz7IP"}'
  ))
)
thought = "**Working out the query**\nI should list files first."
write_case(
  g, "thought_tools", g_tools,
  list(e_start("k9_XaJ3vGsmWz7IP"), e_open("thinking", 1L),
       e_delta("thinking", 1L, "**Working out the query**\n"),
       e_delta("thinking", 1L, "I should list files first."),
       e_end("thinking", 1L, g_think(thought, signature = tsig)),
       e_open("text", 2L), e_delta("text", 2L, "Let me look at "),
       e_delta("text", 2L, "the directory."),
       e_end("text", 2L, g_text("Let me look at the directory.")),
       e_tstart(3L, "fc_7h2k", "find"), e_delta("toolcall", 3L, "{\"pattern\":\"*.R\"}"),
       e_end("toolcall", 3L, g_tool("fc_7h2k", "find", list(pattern = "*.R"), sig = csig)),
       e_tstart(4L, "fc_8j3m", "read"), e_delta("toolcall", 4L, "{\"path\":\"R/a.R\"}"),
       e_end("toolcall", 4L, g_tool("fc_8j3m", "read", list(path = "R/a.R"))),
       e_done("tool_use")),
  g_msg("tool_use", "STOP", rid = "k9_XaJ3vGsmWz7IP",
        content = list(g_think(thought, signature = tsig),
                       g_text("Let me look at the directory."),
                       g_tool("fc_7h2k", "find", list(pattern = "*.R"), sig = csig),
                       g_tool("fc_8j3m", "read", list(path = "R/a.R"))),
        usage = g_usage(300, 74, 512, reasoning = 43))
)

g_sig = c(
  dat(js(
    '{"candidates":[{"content":{"parts":[{"text":"The mean is 20.1."}],"role":"model"},',
    '"index":0}],"modelVersion":"gemini-3.8-flash","responseId":"r2"}'
  )),
  dat(js(
    '{"candidates":[{"content":{"parts":[{"text":"","thoughtSignature":"', xsig, '"}],',
    '"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":',
    '{"promptTokenCount":120,"candidatesTokenCount":8,"totalTokenCount":128},',
    '"modelVersion":"gemini-3.8-flash","responseId":"r2"}'
  ))
)
write_case(
  g, "text_signature", g_sig,
  list(e_start("r2"), e_open("text", 1L), e_delta("text", 1L, "The mean is 20.1."),
       e_end("text", 1L, g_text("The mean is 20.1.", xsig)), e_done("stop")),
  g_msg("stop", "STOP", rid = "r2", content = list(g_text("The mean is 20.1.", xsig)),
        usage = g_usage(120, 8))
)

write_case(
  g, "blocked",
  dat(js(
    '{"promptFeedback":{"blockReason":"SAFETY"},',
    '"usageMetadata":{"promptTokenCount":10,"totalTokenCount":10},"responseId":"r3"}'
  )),
  list(e_start("r3"), e_error("provider")),
  g_msg("error", err = "The prompt was blocked: SAFETY", rid = "r3", usage = g_usage(10))
)

write_case(
  g, "unknown_finish",
  dat(js(
    '{"candidates":[{"content":{"parts":[{"text":"x"}],"role":"model"},',
    '"finishReason":"MISSING_THOUGHT_SIGNATURE","index":0}],"responseId":"r4"}'
  )),
  list(e_start("r4"), e_open("text", 1L), e_delta("text", 1L, "x"),
       e_end("text", 1L, g_text("x")), e_error("provider")),
  g_msg("error", "MISSING_THOUGHT_SIGNATURE",
        err = "Provider stopped with: MISSING_THOUGHT_SIGNATURE", rid = "r4",
        content = list(g_text("x")))
)

write_case(
  g, "truncated",
  dat(js(
    '{"candidates":[{"content":{"parts":[{"text":"Partial"}],"role":"model"},',
    '"index":0}],"responseId":"r5"}'
  )),
  list(e_start("r5"), e_open("text", 1L), e_delta("text", 1L, "Partial"),
       e_end("text", 1L, g_text("Partial")), e_error("network")),
  g_msg("error", err = "The Google stream ended without a finish reason.", rid = "r5",
        content = list(g_text("Partial")))
)
```

Run it again:

```bash
Rscript --vanilla tests/testthat/fixtures/sse/make_fixtures.R
ls tests/testthat/fixtures/sse/google-generative-ai | wc -l
```

Expected: the count is `16` (five cases with three files each, plus `model.json`).

Create `tests/testthat/test-provider-google.R`:

```r
# Tests for R/provider-google.R (plan P12): the google-generative-ai normaliser and request
# body.
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

api = "google-generative-ai"

# ---- the normaliser (Task 8) -------------------------------------------------------------------

test_that("google fixtures give the golden events and final messages (INFRA-02)", {
  expect_all_golden(api, google_normaliser)
})

test_that("google events do not depend on how the bytes are chunked (INFRA-23)", {
  for (case in c("thought_tools", "text_signature", "truncated")) {
    expect_chunk_invariant(api, google_normaliser, case)
  }
})

test_that("thought signatures stay on the part they arrived on (09 section 2.1)", {
  msg = replay_case(api, google_normaliser, "thought_tools")$message
  expect_identical(msg$content[[1L]]$signature, "CiQBjz1rX3NpZ1RoaW5r")
  expect_identical(msg$content[[3L]]$thought_signature, "CiQBjz1rX3NpZ0NhbGw=")
  expect_null(msg$content[[4L]]$thought_signature)
  expect_identical(msg$usage$output, 74)
  expect_identical(msg$usage$cache_read, 512)
  sig = replay_case(api, google_normaliser, "text_signature")$message
  expect_identical(sig$content[[1L]]$signature, "Q2lnVGV4dFNpZw==")
})

test_that("blocked prompts, unknown finish reasons and truncation end in one error event", {
  for (case in c("blocked", "unknown_finish", "truncated")) {
    ev = replay_case(api, google_normaliser, case)$events
    expect_one_terminal(ev)
    expect_identical(ev[[length(ev)]]$type, "error")
  }
  unk = replay_case(api, google_normaliser, "unknown_finish")$message
  expect_identical(unk$raw_stop_reason, "MISSING_THOUGHT_SIGNATURE")
})

test_that("an error chunk before any delta asks the transport to retry", {
  log = event_log()
  retried = event_log()
  n = google_normaliser(test_model(api), list(emit = log$emit, retry = retried$emit))
  expect_false(n$push(list(data = paste0(
    '{"error":{"code":503,"message":"The model is overloaded.","status":"UNAVAILABLE"}}'
  ))))
  expect_identical(retried$events[[1L]]$class, "overloaded")
  expect_identical(retried$events[[1L]]$status, 503L)
  n$finish()
  expect_identical(types_of(log$events), c("start", "error"))
})

test_that("missing or duplicate function-call ids are generated", {
  log = event_log()
  n = google_normaliser(test_model(api), list(emit = log$emit))
  n$push(list(data = paste0('{"candidates":[{"content":{"parts":[',
                            '{"functionCall":{"name":"read","args":{"path":"a"}}},',
                            '{"functionCall":{"name":"read","args":{"path":"b"}}}],',
                            '"role":"model"},"finishReason":"STOP","index":0}],',
                            '"responseId":"abc"}')))
  msg = n$finish()
  ids = vapply(msg$content, function(b) b$id, "")
  expect_identical(ids, c("read_abc_1", "read_abc_2"))
  expect_identical(msg$stop_reason, "tool_use")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-google")'`
Expected: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 1 ]`, with errors such as ``object 'google_normaliser' not found``.

- [ ] **Step 3: Write the implementation**

Create `R/provider-google.R`:

```r
# The google-generative-ai adapter (P12): streamGenerateContent?alt=sse with the key in the
# x-goog-api-key header (report 09 verification row 2: the header keeps the key out of URLs);
# thought signatures kept on the exact part they arrived on and replayed only to the same model;
# unknown finish reasons map to error with the raw value (report 09 sections 2.1-2.2, 3.1, 4.5
# and verification rows 4-9). The normaliser is adapted from the verified Gemini accumulator of
# report 09 section 5.1 and report 03 section 5.3.

#' The Gemini major version of a model id, NA when unknown
#' @noRd
google_major = function(id) {
  m = regmatches(tolower(id), regexec("^gemini(?:-live)?-([0-9]+)", tolower(id), perl = TRUE))
  m = m[[1L]]
  if (length(m) < 2L) NA_integer_ else as.integer(m[[2L]])
}

#' Does the model take thinkingLevel (Gemini 3.x) rather than thinkingBudget (2.5)?
#' (Pi usesGoogleThinkingLevel(), google-shared.ts:72-83)
#' @noRd
google_uses_level = function(id) {
  id = tolower(id)
  grepl("gemini-3(\\.[0-9]+)?-(pro|flash)", id) ||
    id %in% c("gemini-flash-latest", "gemini-flash-lite-latest") || grepl("gemma-?4", id)
}

#' Do function calls and responses carry ids for this model? (Pi requiresToolCallId)
#' @noRd
google_needs_id = function(id) {
  isTRUE(google_major(id) >= 3L) || grepl("^(claude-|gpt-oss-)", tolower(id))
}

#' A replayable thought signature: base64 with a length that is a multiple of 4
#' @noRd
google_valid_sig = function(s) {
  is.character(s) && length(s) == 1L && nzchar(s) && nchar(s) %% 4L == 0L &&
    grepl("^[A-Za-z0-9+/]+={0,2}$", s)
}

#' The thinking budget of a Gemini 2.5 model for a level, -1 (dynamic) when unknown
#' @noRd
google_budget = function(id, level) {
  id = tolower(id)
  lv = if (level %in% c("xhigh", "max")) "high" else level
  tab = if (grepl("2\\.5-pro", id)) {
    c(minimal = 128L, low = 2048L, medium = 8192L, high = 32768L)
  } else if (grepl("2\\.5-flash-lite", id)) {
    c(minimal = 512L, low = 2048L, medium = 8192L, high = 24576L)
  } else if (grepl("2\\.5-flash", id)) {
    c(minimal = 128L, low = 2048L, medium = 8192L, high = 24576L)
  } else {
    NULL
  }
  if (is.null(tab) || !(lv %in% names(tab))) -1L else tab[[lv]]
}

#' A Google error object -> class suffix, HTTP status and retryability (09 section 2.1)
#' @noRd
google_error_info = function(err) {
  st = err$status %||% ""
  code = if (is.numeric(err$code)) as.integer(err$code) else NA_integer_
  if (identical(st, "RESOURCE_EXHAUSTED") || identical(code, 429L)) {
    return(list(class = "rate_limit", status = 429L, retry = TRUE))
  }
  if (st %in% c("UNAVAILABLE", "INTERNAL") || (!is.na(code) && code >= 500L)) {
    return(list(class = "overloaded", status = if (is.na(code)) 503L else code, retry = TRUE))
  }
  if (st %in% c("UNAUTHENTICATED", "PERMISSION_DENIED")) {
    return(list(class = "auth", status = if (is.na(code)) 401L else code, retry = FALSE))
  }
  list(class = "provider", status = code, retry = FALSE)
}

#' The google-generative-ai normaliser (04 section 8.1; Pi google-generative-ai.ts:106-278)
#' @noRd
google_normaliser = function(model, opts) {
  st = adp_state(model, opts)
  cur = new.env(parent = emptyenv())
  cur$open = NULL
  cur$calls = 0L
  cur$finish = NULL

  close_open = function() {
    if (!is.null(cur$open)) adp_close(st, cur$open)
    cur$open = NULL
  }

  on_call = function(p) {
    close_open()
    fc = p$functionCall
    cur$calls = cur$calls + 1L
    ids = vapply(Filter(function(b) identical(b$type, "tool_call"), st$blocks),
                 function(b) b$id %||% "", "")
    id = fc$id
    if (is.null(id) || !nzchar(id) || id %in% ids) {
      frag = substr(gsub("[^A-Za-z0-9]", "", st$response_id %||% "x"), 1L, 12L)
      id = paste0(gsub("[^A-Za-z0-9_-]", "_", fc$name %||% "call"), "_", frag, "_", cur$calls)
    }
    args = fc$args
    if (!adp_is_object(args) || !length(args)) args = json_obj()
    i = adp_open(st, "tool_call", id = id, name = fc$name %||% "", args = args,
                 thought_signature = p$thoughtSignature)
    adp_delta(st, i, json_encode(args))
    adp_close(st, i)
  }

  push = function(ev) {
    if (st$terminal || !is.null(st$pending)) return(st$terminal)
    data = ev$data %||% ""
    if (!nzchar(data)) return(FALSE)
    ch = adp_json_try(data)
    if (!adp_is_object(ch)) {
      adp_error(st, paste0("Could not parse a Gemini stream chunk: ", substr(data, 1L, 200L)))
      return(TRUE)
    }
    if (!is.null(ch$error)) {
      info = google_error_info(ch$error)
      msg = paste0(ch$error$status %||% "error", ": ", ch$error$message %||% "unknown error")
      return(adp_stream_error(st, opts, msg, class = info$class, status = info$status,
                              retryable = info$retry))
    }
    if (is.null(st$response_id) && !is.null(ch$responseId)) st$response_id = ch$responseId
    mv = ch$modelVersion
    if (is.character(mv) && !identical(mv, model$id)) st$response_model = mv
    u = ch[["usageMetadata"]]
    if (!is.null(u)) {
      cached = u[["cachedContentTokenCount"]] %||% 0
      thoughts = u[["thoughtsTokenCount"]] %||% 0
      st$usage = list(input = (u[["promptTokenCount"]] %||% 0) - cached,
                      output = (u[["candidatesTokenCount"]] %||% 0) + thoughts,
                      cache_read = cached, reasoning = thoughts)
    }
    cand = if (length(ch$candidates)) ch$candidates[[1L]] else NULL
    if (is.null(cand)) {
      reason = ch$promptFeedback$blockReason
      if (!is.null(reason)) {
        adp_error(st, paste0("The prompt was blocked: ", reason), class = "provider")
        return(TRUE)
      }
      return(FALSE)
    }
    for (p in cand$content$parts %||% list()) {
      if (!is.null(p[["text"]])) {
        kind = if (isTRUE(p[["thought"]])) "thinking" else "text"
        if (is.null(cur$open) || st$blocks[[cur$open]]$type != kind) {
          close_open()
          cur$open = adp_open(st, kind)
        }
        adp_delta(st, cur$open, p$text)
        if (nzchar(p$thoughtSignature %||% "")) {
          st$blocks[[cur$open]]$signature = p$thoughtSignature
        }
      }
      if (!is.null(p$functionCall)) on_call(p)
    }
    fr = cand$finishReason
    if (!is.null(fr)) {
      cur$finish = fr
      st$raw_stop = fr
      has_tool = any(vapply(st$blocks, function(b) identical(b$type, "tool_call"), logical(1)))
      st$stop_reason = if (fr == "STOP") {
        if (has_tool) "tool_use" else "stop"
      } else if (fr == "MAX_TOKENS") {
        "length"
      } else {
        "error"
      }
      if (identical(st$stop_reason, "error")) {
        detail = if (is.null(cand$finishMessage)) "" else paste0(": ", cand$finishMessage)
        st$error_message = paste0("Provider stopped with: ", fr, detail)
      }
    }
    FALSE
  }

  finish = function() {
    if (st$terminal) return(st$final)
    if (!is.null(st$pending)) return(adp_finish_pending(st))
    close_open()
    if (is.null(cur$finish)) {
      return(adp_error(st, "The Google stream ended without a finish reason.",
                       class = "network"))
    }
    adp_done(st)
  }

  adp_normaliser(st, push, finish)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-google")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 56 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-google.R tests/testthat/test-provider-google.R tests/testthat/fixtures/sse/make_fixtures.R tests/testthat/fixtures/sse/google-generative-ai
git commit -m "feat(provider): add the google-generative-ai normaliser"
```

---

### Task 9: Gemini request bodies and `builtin:google`

**Files:**
- Modify: `R/provider-google.R` (append)
- Modify: `tests/testthat/fixtures/sse/replay_helpers.R` (append)
- Test: `tests/testthat/test-provider-google.R` (append)

**Interfaces:**
- Consumes: the Task 2 request helpers, `gptr_adapter()`, `ext_declare_builtin()`, `on_load()`, `json_encode()`, `json_obj()` (P01/P02); tests as in Task 2, plus the Task 7 helpers `handoff_entries()` and `wire_object()`, P05's `project_messages()`, P01's `schema_validate()` and the Task 6 `responses_normaliser()` (the INFRA-08 chain Anthropic -> Responses -> Gemini).
- Produces: `google_build(model, context, opts)`, `google_caps()`, `google_schema(x)`, `google_image()`, `google_user()`, `google_assistant()`, `google_tool_results()`, `google_generation(model, params)`, `builtin_google(gptr)` and the registered adapter `google-generative-ai`. Test helper (in `replay_helpers.R`): `gemini_body_schema()` (the Gemini schema fixture of INFRA-08).

Body rules (report 09 sections 2.1, 3.1, 4.5 and verification rows 2, 5-7, 9; G4 sections 2.5, 3.7): key order `systemInstruction` (`parts = [T0, T1]`), `tools` (`functionDeclarations` with `parametersJsonSchema`, converted once per session), `toolConfig.functionCallingConfig` (`AUTO`; `NONE` for `tool_choice = "none"`; `ANY`, with `allowedFunctionNames` for one named tool, when forced choice is allowed and `returns` is not set), `generationConfig` (`maxOutputTokens`, `temperature`, `thinkingConfig`: `thinkingLevel` in upper case on Gemini 3.x with `xhigh` and `max` clamped to `HIGH` and `off` sent as the lowest level the model accepts, `thinkingBudget` on 2.5 with `0` for `off` and `-1` for dynamic), the declared request params (`labels`, `serviceTier`), `contents` last. No cache markers: Gemini caches implicitly. A thought signature replays only to the same model and only on the part it arrived on, and only when it is valid base64; Gemini 3 calls and responses carry ids; tool results are one user content of `functionResponse` parts (`response.output` or `response.error`), with images inside `functionResponse.parts` on Gemini 3 and in a following user content on 2.5; operator messages and `returns` instructions are user contents. The key travels in `x-goog-api-key`, never in the URL.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/fixtures/sse/replay_helpers.R`:

```r
# The schema fixture of a Gemini request body (report 09 section 2.1; G4 section 3.7): the fields,
# contents and parts gptr sends, closed, so a foreign key such as a signature fails
gemini_body_schema = function() {
  str = list(type = "string")
  obj = list(type = "object")
  int = list(type = "integer")
  inline = wire_object(list(mimeType = str, data = str), c("mimeType", "data"))
  call = wire_object(list(name = str, args = obj, id = str), c("name", "args"))
  response = wire_object(list(name = str, response = obj, id = str, parts = list(type = "array")),
                         c("name", "response"))
  part = wire_object(list(text = str, thought = list(type = "boolean"), thoughtSignature = str,
                          inlineData = inline, functionCall = call, functionResponse = response))
  parts = list(type = "array", items = part)
  decl = wire_object(list(name = str, description = str, parametersJsonSchema = obj), "name")
  tool = wire_object(list(functionDeclarations = list(type = "array", items = decl)))
  calling = wire_object(list(mode = list(type = "string", enum = c("AUTO", "ANY", "NONE")),
                             allowedFunctionNames = list(type = "array", items = str)), "mode")
  thinking = wire_object(list(includeThoughts = list(type = "boolean"), thinkingLevel = str,
                              thinkingBudget = int))
  generation = wire_object(list(maxOutputTokens = int, temperature = list(type = "number"),
                                thinkingConfig = thinking))
  content = wire_object(list(role = list(type = "string", enum = c("user", "model")),
                             parts = parts), c("role", "parts"))
  top = list(systemInstruction = wire_object(list(parts = parts), "parts"),
             tools = list(type = "array", items = tool),
             toolConfig = wire_object(list(functionCallingConfig = calling)),
             generationConfig = generation, labels = obj, serviceTier = str,
             contents = list(type = "array", items = content))
  wire_object(top, "contents")
}
```

Append to `tests/testthat/test-provider-google.R`:

```r
# ---- the request body and the built-in (Task 9) ------------------------------------------------

test_that("Gemini bodies: systemInstruction, tools, toolConfig, generationConfig, contents", {
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  req = google_build(model, ctx_fixture(list(first_message())),
                     list(base_url = "https://generativelanguage.googleapis.com/v1beta",
                          credential = fake_handle("GEMINI_API_KEY")))
  body = json_decode(req$body)
  expect_identical(names(body), c("systemInstruction", "tools", "toolConfig", "generationConfig",
                                  "contents"))
  expect_identical(body$systemInstruction$parts[[1L]]$text, "T0 static sections.")
  decl = body$tools[[1L]]$functionDeclarations[[2L]]
  expect_identical(decl$name, "r")
  expect_identical(decl$parametersJsonSchema$required, list("code"))
  expect_equal(body$toolConfig, list(functionCallingConfig = list(mode = "AUTO")))
  expect_equal(body$generationConfig, list(maxOutputTokens = 1024L,
                                           thinkingConfig = list(includeThoughts = TRUE)))
  expect_identical(req$url, paste0("https://generativelanguage.googleapis.com/v1beta/models/",
                                   "gemini-3.8-flash:streamGenerateContent?alt=sse"))
  expect_identical(req$headers$`x-goog-api-key`, fake_handle("GEMINI_API_KEY"))
  expect_false(grepl("key=", req$url, fixed = TRUE))
})

test_that("the default cache policy gives Gemini no markers: implicit caching (acceptance 4)", {
  plan = default_plan(api)
  expect_identical(plan$anchors, character())
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  body = google_build(model, ctx_fixture(list(first_message()), cache_plan = plan), list())$body
  expect_false(grepl("cache", body, ignore.case = TRUE))
  expect_identical(names(json_decode(body))[[1L]], "systemInstruction")
})

test_that("thought signatures replay byte for byte to the same model only (acceptance 2)", {
  dir = sse_dir(api)
  model = adp_fixture_model(api, dir)
  msg = replay_case(api, google_normaliser, "thought_tools")$message
  ctx = ctx_fixture(list(first_message(), msg, msg_tool_result("fc_7h2k", "find", "a.R"),
                         msg_tool_result("fc_8j3m", "read", "x = 1")))
  body = json_decode(google_build(model, ctx, list())$body)
  parts = body$contents[[2L]]$parts
  expect_identical(parts[[1L]], list(thought = TRUE, text = msg$content[[1L]]$thinking,
                                     thoughtSignature = "CiQBjz1rX3NpZ1RoaW5r"))
  expect_identical(parts[[3L]]$thoughtSignature, "CiQBjz1rX3NpZ0NhbGw=")
  expect_identical(parts[[3L]]$functionCall$id, "fc_7h2k")
  expect_null(parts[[4L]]$thoughtSignature)
  results = body$contents[[3L]]
  expect_identical(results$role, "user")
  expect_identical(results$parts[[1L]]$functionResponse,
                   list(name = "find", response = list(output = "a.R"), id = "fc_7h2k"))
  other = json_decode(google_build(test_model(api, provider = "google", id = "gemini-3.5-flash"),
                                   ctx, list())$body)
  expect_false(grepl("thoughtSignature", json_encode(other$contents), fixed = TRUE))
  expect_null(other$contents[[2L]]$parts[[1L]]$thought)
})

test_that("Anthropic -> Responses -> Gemini: no foreign opaque data, valid body (INFRA-08)", {
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  resp = replay_case("openai-responses", responses_normaliser, "reasoning_tools")$message
  h = handoff_entries(list(msg_user("And the row count?", timestamp = 5), resp,
                           msg_tool_result("call_fixture1|fc_fixture1", "r", "[1] 32",
                                           timestamp = 7)))
  expect_length(h$opaque, 5L)
  # P05's projection (project_messages() ends with handoff_transform()), as request_build() runs it
  msgs = project_messages(h$entries, h$leaf, model)
  wire = google_build(model, ctx_fixture(msgs), list())$body
  for (s in h$opaque) expect_false(grepl(s, wire, fixed = TRUE), label = s)
  expect_false(grepl("thoughtSignature|rs_fixture1|msg_fixture1", wire))
  body = json_decode(wire)
  expect_identical(schema_validate(gemini_body_schema(), body)$errors, character())
  expect_identical(names(body), c("systemInstruction", "tools", "toolConfig", "generationConfig",
                                  "contents"))
  roles = vapply(body$contents, function(x) x$role, "")
  expect_identical(roles, c("user", "model", "user", "user", "model", "user"))
  part_ids = function(contents, field) {
    unlist(lapply(contents, function(x) lapply(x$parts, function(p) p[[field]]$id)))
  }
  calls = part_ids(body$contents[roles == "model"], "functionCall")
  expect_identical(calls, c("toolu_01A", "toolu_01B", "call_fixture1_fc_fixture1"))
  expect_identical(part_ids(body$contents[roles == "user"], "functionResponse"), calls)
  expect_identical(body$contents[[5L]]$parts[[1L]],
                   list(text = "**Planning** Need nrow of the data."))
  # the schema is closed: an Anthropic signature on a part does not validate
  bad = body
  bad$contents[[2L]]$parts[[1L]]$signature = h$opaque[[1L]]
  expect_false(schema_validate(gemini_body_schema(), bad)$ok)
})

test_that("tool-result images ride in functionResponse.parts on Gemini 3 (09 section 2.1)", {
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  asst = msg_assistant(list(block_tool_call("fc_1", "r", list(code = "plot(1)"))), api = api,
                       provider = "google", model = "gemini-3.8-flash", stop_reason = "tool_use")
  res = msg_tool_result("fc_1", "r", list(block_text("drawn"), block_image(png_b64())))
  body = json_decode(google_build(model, ctx_fixture(list(msg_user("plot"), asst, res)),
                                  list())$body)
  fr = body$contents[[3L]]$parts[[1L]]$functionResponse
  expect_identical(fr$parts[[1L]]$inlineData$data, png_b64())
  old = test_model(api, provider = "google", id = "gemini-2.5-flash")
  body = json_decode(google_build(old, ctx_fixture(list(msg_user("plot"), asst, res)),
                                  list())$body)
  expect_identical(body$contents[[4L]]$parts[[1L]]$text, "Tool result image:")
  expect_null(body$contents[[3L]]$parts[[1L]]$functionResponse$id)
})

test_that("thinking levels for Gemini 3, budgets for 2.5, forced calls as mode ANY", {
  g3 = test_model(api, provider = "google", id = "gemini-3.8-flash",
                  thinking_levels = c("low", "medium", "high"))
  body = json_decode(google_build(g3, ctx_fixture(list(msg_user("x")),
                                                  params = list(thinking = "xhigh")),
                                  list())$body)
  expect_equal(body$generationConfig$thinkingConfig,
               list(includeThoughts = TRUE, thinkingLevel = "HIGH"))
  body = json_decode(google_build(g3, ctx_fixture(list(msg_user("x")),
                                                  params = list(thinking = "off")),
                                  list())$body)
  expect_equal(body$generationConfig$thinkingConfig, list(thinkingLevel = "LOW"))
  g25 = test_model(api, provider = "google", id = "gemini-2.5-pro")
  body = json_decode(google_build(g25, ctx_fixture(list(msg_user("x")),
                                                   params = list(thinking = "medium")),
                                  list())$body)
  expect_equal(body$generationConfig$thinkingConfig,
               list(includeThoughts = TRUE, thinkingBudget = 8192L))
  forced = list(tool_choice = list(type = "tool", name = "read"))
  body = json_decode(google_build(g3, ctx_fixture(list(msg_user("x")), params = forced),
                                  list())$body)
  expect_equal(body$toolConfig$functionCallingConfig,
               list(mode = "ANY", allowedFunctionNames = list("read")))
})

test_that("returns = becomes a user instruction; operators are user contents (IC-71)", {
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  relay = msg_operator("steer_relay", "The user sent this message while you were working: stop")
  body = json_decode(google_build(model, ctx_fixture(list(msg_user("x"), relay),
                                                     params = list(returns = count_schema())),
                                  list())$body)
  n = length(body$contents)
  expect_identical(body$contents[[n - 1L]]$parts[[1L]]$text,
                   "The user sent this message while you were working: stop")
  expect_match(body$contents[[n]]$parts[[1L]]$text, "JSON Schema", fixed = TRUE)
  expect_null(body$generationConfig$responseJsonSchema)
})

test_that("the frozen prefix stays byte-identical across turns (acceptance 4)", {
  model = test_model(api, provider = "google", id = "gemini-3.8-flash")
  asst = msg_assistant(list(block_tool_call("fc_1", "r", list(code = "nrow(d)"),
                                            thought_signature = "Q2lnRmNTaWc=")),
                       api = api, provider = "google", model = "gemini-3.8-flash",
                       stop_reason = "tool_use", timestamp = 2)
  turn2 = list(first_message(), asst, msg_tool_result("fc_1", "r", "[1] 32"))
  memo = new.env(parent = emptyenv())
  b1 = google_build(model, ctx_fixture(list(first_message())), list(memo = memo))$body
  b2 = google_build(model, ctx_fixture(turn2), list(memo = memo))$body
  expect_true(startsWith(b2, substr(b1, 1L, nchar(b1) - 2L)))
  expect_identical(b2, google_build(model, ctx_fixture(turn2), list())$body)
  expect_true(grepl("\"thoughtSignature\":\"Q2lnRmNTaWc=\"", b2, fixed = TRUE))
})

test_that("builtin:google registers the adapter; check_adapter() and gptr_check() pass", {
  a = adapter_get(api)
  expect_identical(a$capabilities$tool_shape, "gemini")
  expect_identical(a$capabilities$cache, "gemini")
  res = check_adapter(a, fixtures = sse_dir(api))
  expect_true(all(res$ok), label = paste(res$check[!res$ok], collapse = "; "))
  expect_true("adapter.thought_tools.roundtrip" %in% res$check)
  expect_true(all(gptr_check(a)$ok))
})

test_that("end to end on the mock server: a Gemini stream (skip on CRAN)", {
  skip_on_cran()
  srv = local_mock_server("gemini", n = 3L, interval = 0.02)
  r = mock_stream(srv)
  expect_identical(r$types, c("start", "text_start", rep("text_delta", 3L), "text_end", "done"))
  expect_identical(msg_text(r$message), "tok01 tok02 tok03 ")
  expect_identical(r$message$stop_reason, "stop")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-google")'`
Expected: `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 57 ]`, with errors such as ``could not find function "google_build"`` and `No adapter is registered for the api google-generative-ai.`

- [ ] **Step 3: Write the implementation**

Append to `R/provider-google.R`:

```r
#' Adapter capabilities of google-generative-ai (04 section 8.1; IC-69, IC-71)
#' @noRd
google_caps = function() {
  list(images_in_results = TRUE, tool_addition = FALSE, structured_output = FALSE,
       reasoning_replay = TRUE, parallel_tools = TRUE, forced_tool_choice = TRUE,
       request_params = c("labels", "service_tier"), operator_role = "user", cache = "gemini",
       max_tool_name = 128L, tool_shape = "gemini")
}

#' Remove the JSON Schema keywords Gemini rejects in parametersJsonSchema
#' @noRd
google_schema = function(x) {
  if (!is.list(x)) return(x)
  if (!is.null(names(x))) x = x[!(names(x) %in% c("$schema", "$id", "$comment"))]
  if (length(x)) x[] = lapply(x, google_schema)
  x
}

#' A Gemini inlineData part, or a text note for a text-only model
#' @noRd
google_image = function(b, images) {
  if (!images) return(list(text = adp_image_note()))
  list(inlineData = list(mimeType = b$mime, data = b$data))
}

#' The Gemini content of a user message
#' @noRd
google_user = function(m, images) {
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    if (type %in% c("text", "context") && nzchar(b$text)) {
      parts[[length(parts) + 1L]] = list(text = b$text)
    } else if (type == "image") {
      parts[[length(parts) + 1L]] = google_image(b, images)
    }
  }
  if (!length(parts)) return(NULL)
  list(role = "user", parts = parts)
}

#' The Gemini model content of an assistant message; thought signatures stay on the part they
#' arrived on and are replayed only to the same model (09 section 2.1)
#' @noRd
google_assistant = function(m, model) {
  same = adp_same_model(m, model)
  needs_id = google_needs_id(model$id)
  parts = list()
  for (b in m$content) {
    type = b$type %||% ""
    p = NULL
    if (type == "text") {
      sig = if (same && google_valid_sig(b$signature)) b$signature else NULL
      if (nzchar(trimws(b$text)) || !is.null(sig)) p = list(text = b$text)
      if (!is.null(p) && !is.null(sig)) p$thoughtSignature = sig
    } else if (type == "thinking") {
      sig = if (same && google_valid_sig(b$signature)) b$signature else NULL
      if (nzchar(trimws(b$thinking)) || !is.null(sig)) {
        p = if (same) list(thought = TRUE, text = b$thinking) else list(text = b$thinking)
        if (!is.null(sig)) p$thoughtSignature = sig
      }
    } else if (type == "tool_call") {
      sig = if (same && google_valid_sig(b$thought_signature)) b$thought_signature else NULL
      fc = list(name = b$name, args = if (length(b$arguments)) b$arguments else json_obj())
      if (needs_id) fc$id = adp_sanitize_id(b$id)
      p = c(list(functionCall = fc), if (!is.null(sig)) list(thoughtSignature = sig))
    }
    if (!is.null(p)) parts[[length(parts) + 1L]] = p
  }
  if (!length(parts)) return(NULL)
  list(role = "model", parts = parts)
}

#' The Gemini contents of a group of tool results: one user content of functionResponse parts;
#' images inside functionResponse.parts on Gemini 3+, else a following user content
#' @noRd
google_tool_results = function(group, model) {
  needs_id = google_needs_id(model$id)
  v3 = isTRUE(google_major(model$id) >= 3L)
  images = adp_images_ok(model)
  parts = list()
  extra = list()
  for (r in group) {
    txt = paste(vapply(Filter(function(b) identical(b$type, "text"), r$content),
                       function(b) b$text, ""), collapse = "\n")
    fr = list(name = r$tool_name,
              response = if (isTRUE(r$is_error)) list(error = txt) else list(output = txt))
    if (needs_id) fr$id = adp_sanitize_id(r$tool_call_id)
    imgs = lapply(Filter(function(b) identical(b$type, "image"), r$content), google_image,
                  images = images)
    if (length(imgs) && v3 && images) fr$parts = imgs
    if (length(imgs) && !(v3 && images)) extra = c(extra, imgs)
    parts[[length(parts) + 1L]] = list(functionResponse = fr)
  }
  out = list(list(role = "user", parts = parts))
  if (length(extra)) {
    out[[2L]] = list(role = "user", parts = c(list(list(text = "Tool result image:")), extra))
  }
  out
}

#' The generationConfig of a request: maxOutputTokens, temperature and thinkingConfig
#' (thinkingLevel for Gemini 3.x, thinkingBudget for 2.5; 09 sections 2.1 and 4.5)
#' @noRd
google_generation = function(model, params) {
  gen = json_obj()
  if (!is.null(params$max_tokens)) gen$maxOutputTokens = as.integer(params$max_tokens)
  if (!is.null(params$temperature)) gen$temperature = params$temperature
  if (!isTRUE(model$reasoning)) return(gen)
  level = params$thinking
  if (google_uses_level(model$id)) {
    if (is.null(level)) {
      gen$thinkingConfig = list(includeThoughts = TRUE)
    } else if (identical(level, "off")) {
      low = if ("minimal" %in% unlist(model$thinking_levels)) "MINIMAL" else "LOW"
      gen$thinkingConfig = list(thinkingLevel = low)
    } else {
      lv = if (level %in% c("xhigh", "max")) "high" else level
      gen$thinkingConfig = list(includeThoughts = TRUE, thinkingLevel = toupper(lv))
    }
  } else if (identical(level, "off")) {
    gen$thinkingConfig = list(thinkingBudget = 0L)
  } else {
    budget = if (is.null(level)) -1L else google_budget(model$id, level)
    gen$thinkingConfig = list(includeThoughts = TRUE, thinkingBudget = budget)
  }
  gen
}

#' build() of the google-generative-ai adapter (04 section 8.1; G4 section 3.7:
#' systemInstruction, tools, toolConfig, generationConfig, contents; implicit caching only)
#' @noRd
google_build = function(model, context, opts) {
  params = context$params %||% list()
  msgs = context$messages %||% list()
  images = adp_images_ok(model)
  head = json_obj()
  sys = list()
  for (k in c("t0", "t1")) {
    txt = context$system[[k]] %||% ""
    if (nzchar(txt)) sys[[length(sys) + 1L]] = list(text = txt)
  }
  if (length(sys)) head$systemInstruction = list(parts = sys)
  extra = character()
  tj = adp_tools_json(opts, "google", context$tools_json, function(tools) {
    decl = lapply(tools, function(t) {
      list(name = t$name, description = t$description %||% "",
           parametersJsonSchema = google_schema(t$input_schema))
    })
    list(list(functionDeclarations = decl))
  })
  if (!is.null(tj)) {
    extra = c(extra, paste0("\"tools\":", tj))
    tc = params$tool_choice
    fcc = if (identical(tc, "none")) {
      list(mode = "NONE")
    } else if (adp_forced(tc) && adp_forced_ok(model, google_caps()) && is.null(params$returns)) {
      if (identical(tc$type, "any")) list(mode = "ANY") else
        list(mode = "ANY", allowedFunctionNames = list(tc$name))
    } else {
      list(mode = "AUTO")
    }
    extra = c(extra, paste0("\"toolConfig\":", json_encode(list(functionCallingConfig = fcc))))
  }
  gen = google_generation(model, params)
  if (length(gen)) extra = c(extra, paste0("\"generationConfig\":", json_encode(gen)))
  if (!is.null(params$labels)) extra = c(extra, paste0("\"labels\":", json_encode(params$labels)))
  if (!is.null(params$service_tier)) {
    extra = c(extra, paste0("\"serviceTier\":", json_encode(params$service_tier)))
  }

  elements = character()
  n = length(msgs)
  i = 1L
  while (i <= n) {
    m = msgs[[i]]
    r = m$role %||% ""
    if (r == "tool_result") {
      j = i
      while (j <= n && identical(msgs[[j]]$role, "tool_result")) j = j + 1L
      group = msgs[i:(j - 1L)]
      key = paste(c("google", "results", model$id, images, vapply(group, adp_msg_key, "")),
                  collapse = "|")
      el = adp_memo(opts, key, function() {
        paste(vapply(google_tool_results(group, model), json_encode, ""), collapse = ",")
      })
      elements = c(elements, el)
      i = j
      next
    }
    same = adp_same_model(m, model)
    key = paste("google", r, adp_msg_key(m), same, model$id, images, sep = "|")
    el = adp_memo(opts, key, function() {
      x = NULL
      if (r == "user") x = google_user(m, images)
      if (r == "assistant") x = google_assistant(m, model)
      if (r == "operator") {
        txt = adp_operator_text(m)
        if (nzchar(txt)) x = list(role = "user", parts = list(list(text = txt)))
      }
      if (is.null(x)) "" else json_encode(x)
    })
    if (nzchar(el)) elements = c(elements, el)
    i = i + 1L
  }
  if (!is.null(params$returns)) {
    text = adp_returns_instruction(params$returns)
    elements = c(elements, json_encode(list(role = "user", parts = list(list(text = text)))))
  }

  headers = list(`content-type` = "application/json", accept = "text/event-stream")
  if (!is.null(opts$credential)) headers$`x-goog-api-key` = adp_header_secret(opts$credential)
  headers = c(headers, adp_provider_headers(model))
  path = paste0("models/", model$id, ":streamGenerateContent?alt=sse")
  list(url = adp_url(opts$base_url %||% "https://generativelanguage.googleapis.com/v1beta", path),
       method = "POST", headers = headers,
       body = adp_body(head, extra, "contents", elements), stream = "sse")
}

#' builtin:google: registers the google-generative-ai adapter (04 sections 7.12, 10.3)
#' @noRd
builtin_google = function(gptr) {
  gptr$register(gptr_adapter("google-generative-ai", transport = "http_sse",
                             build = google_build, parse = google_normaliser,
                             capabilities = google_caps()))
  invisible(NULL)
}

on_load(ext_declare_builtin("google", builtin_google))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "provider-google")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 111 ]`

- [ ] **Step 5: Commit**

```bash
git add R/provider-google.R tests/testthat/test-provider-google.R
git commit -m "feat(provider): build google-generative-ai request bodies and register builtin:google"
```

---

### Task 10: Gated live tests

**Files:**
- Create: `tests/testthat/test-live-anthropic.R`, `tests/testthat/test-live-openai.R`, `tests/testthat/test-live-google.R`
- Modify: `tests/testthat/fixtures/sse/replay_helpers.R` (append)

**Interfaces:**
- Consumes: `model_resolve(ref, strict = TRUE)`, `provider_stream(model, context, opts, emit, done, run = NULL)` (P05), `reactor_pump()` (P04), `msg_user()`, `msg_tool_result()`, `msg_text()`, `json_verbatim()` (P01), and `ctx_fixture()` (Task 2).
- Produces: `skip_unless_live(keys)`, `live_stream(model, context)`, `live_context(messages, params = list())`, `expect_live_round_trip(ref, thinking = "low")` (test helpers).

Each live test makes paid requests and therefore runs only with `GPTR_LIVE_TESTS=true` and the provider's key (conventions sections 2 and 7; P01's `setup.R` blanks the provider keys unless `GPTR_LIVE_TESTS=true`). A round trip is a text turn, then a tool call answered with a result and replayed to the same model with its thinking, signatures, reasoning items or thought signatures, which is the live counterpart of acceptance 2. Keys are never printed: they reach the request only as origin-bound handles through P05's `provider_credential()`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-live-anthropic.R`:

```r
# Live test of the anthropic-messages adapter (plan P12). It makes paid API calls and runs only
# with GPTR_LIVE_TESTS=true and ANTHROPIC_API_KEY set (conventions section 7).
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

test_that("anthropic: a text turn and a tool round trip with thinking replay (live)", {
  skip_unless_live("ANTHROPIC_API_KEY")
  expect_live_round_trip("anthropic/claude-sonnet-5-5")
})
```

Create `tests/testthat/test-live-openai.R`:

```r
# Live test of the openai-responses adapter (plan P12). It makes paid API calls and runs only
# with GPTR_LIVE_TESTS=true and OPENAI_API_KEY set (conventions section 7).
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

test_that("openai: a text turn and a tool round trip with reasoning replay (live)", {
  skip_unless_live("OPENAI_API_KEY")
  expect_live_round_trip("openai/gpt-6-sol")
})
```

Create `tests/testthat/test-live-google.R`:

```r
# Live test of the google-generative-ai adapter (plan P12). It makes paid API calls and runs only
# with GPTR_LIVE_TESTS=true and GEMINI_API_KEY or GOOGLE_API_KEY set (conventions section 7).
source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)

test_that("google: a text turn and a tool round trip with thought signatures (live)", {
  skip_unless_live(c("GEMINI_API_KEY", "GOOGLE_API_KEY"))
  expect_live_round_trip("google/gemini-3.8-flash")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^live-(anthropic|openai|google)$")'`
Expected: `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 0 ]`, with errors such as ``could not find function "skip_unless_live"``.

- [ ] **Step 3: Write the implementation**

Append to `tests/testthat/fixtures/sse/replay_helpers.R`:

```r
# ---- live tests (opt-in: GPTR_LIVE_TESTS=true and the provider's key) ----------------------------

# Skip unless live tests are switched on and one of the key variables is set
skip_unless_live = function(keys) {
  testthat::skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"),
                        "live tests need GPTR_LIVE_TESTS=true")
  testthat::skip_if(!any(nzchar(Sys.getenv(keys))), paste(keys, collapse = " or "))
}

# One real request through provider_stream() and the reactor; returns the final message
live_stream = function(model, context) {
  out = new.env(parent = emptyenv())
  out$message = NULL
  provider_stream(model, context, list(memo = new.env(parent = emptyenv())),
                  emit = function(ev) NULL, done = function(msg) out$message = msg)
  reactor_pump(until = function() !is.null(out$message), timeout = 180)
  out$message
}

# A live context: a terse system prompt, the `count` tool and the given messages
live_context = function(messages, params = list()) {
  tools = json_verbatim(paste0(
    '[{"name":"count","description":"Count the rows of the data set d.",',
    '"input_schema":{"type":"object","properties":{}}}]'
  ))
  ctx = ctx_fixture(messages, params = params, t1 = "")
  ctx$system$t0 = "You are a terse assistant inside an R session."
  ctx$tools_json = tools
  ctx$params$max_tokens = 4096L
  ctx
}

# A text turn, then a tool round trip whose second request replays the first reply (with any
# thinking, signatures, reasoning items or thought signatures) to the same model
expect_live_round_trip = function(ref, thinking = "low") {
  model = model_resolve(ref)
  params = list(thinking = thinking)
  first = live_stream(model, live_context(list(msg_user("Reply with the single word: ready.")),
                                          params))
  testthat::expect_identical(first$stop_reason, "stop", info = first$error_message %||% "")
  testthat::expect_match(tolower(msg_text(first)), "ready")
  ask = msg_user("Use the count tool to count the rows of d, then tell me the number.")
  turn1 = live_stream(model, live_context(list(ask), params))
  testthat::expect_identical(turn1$stop_reason, "tool_use", info = turn1$error_message %||% "")
  calls = Filter(function(b) identical(b$type, "tool_call"), turn1$content)
  results = lapply(calls, function(b) msg_tool_result(b$id, b$name, "32"))
  turn2 = live_stream(model, live_context(c(list(ask, turn1), results), params))
  testthat::expect_identical(turn2$stop_reason, "stop", info = turn2$error_message %||% "")
  testthat::expect_match(msg_text(turn2), "32", fixed = TRUE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^live-(anthropic|openai|google)$")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 3 | PASS 0 ]` (each skipped with "live tests need GPTR_LIVE_TESTS=true"; the filter selects only this plan's three live files, never P06's `test-session-live.R`). The maintainer's opt-in run is `GPTR_LIVE_TESTS=true Rscript --vanilla -e 'devtools::test(filter = "^live-(anthropic|openai|google)$")'` (the conventions' `filter = "live"` also runs P06's `test-session-live.R`, which is harmless there) with `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and `GEMINI_API_KEY` (or `GOOGLE_API_KEY`) set; it is not part of this task's automated checks.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-live-anthropic.R tests/testthat/test-live-openai.R tests/testthat/test-live-google.R tests/testthat/fixtures/sse/replay_helpers.R
git commit -m "test(provider): add gated live round trips for the native adapters"
```

---

## Plan acceptance

Every acceptance check of 05 P12 (including its review amendments), the task and test that prove it, and the command with its expected result. Run from the repository root after Task 10, with P01-P07 in place and the P02 precondition of the Global Constraints met.

| # | Acceptance check (05 P12) | Proven by | Command and expected result |
|---|---|---|---|
| 1 | `devtools::test(filter = "provider-(anthropic\|openai\|google)")` is green; live tests skip unless `GPTR_LIVE_TESTS=true` | Tasks 1-9 (all four test files); Task 10 (the three live files skip) | `Rscript --vanilla -e 'devtools::test(filter = "provider-(anthropic\|openai\|google)")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 604 ]` (under `R CMD check --as-cran`: `SKIP 5`, the four mock-server tests and the linear-time test); `Rscript --vanilla -e 'devtools::test(filter = "^live-(anthropic\|openai\|google)$")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 3 \| PASS 0 ]` |
| 2 | `gptr_check()` passes for each adapter: golden event sequences per fixture; a server error event and a truncated connection each give exactly one `error` event with the partial; chunk invariance; byte-identical re-serialisation of thinking + signature + redacted thinking + parallel tool use (Anthropic), encrypted reasoning with `fc_`/`call_` ids (Responses), thought signatures (Gemini) | Task 3 ("check_adapter() passes for anthropic-messages on its fixtures (acceptance 2)", "the check.adapter service makes gptr_check() replay the fixtures (acceptance 2)"); Tasks 5, 7, 9 ("builtin:... registers the adapter; check_adapter() and gptr_check() pass"); adapters with nothing to replay: Task 3 ("check_adapter() reports missing fixtures and skips inprocess and classifier adapters"); one-error tests: Task 1 ("a server error event and a truncated stream each end with one error and the partial"), Task 4 ("a mid-stream error chunk and a truncated stream each give one error event"), Task 6 ("failed and truncated streams each end with one error event and the partial"), Task 8 ("blocked prompts, unknown finish reasons and truncation end in one error event"); chunk invariance: the `... do not depend on how the bytes are chunked (INFRA-23)` tests of Tasks 1, 4, 6, 8; re-serialisation: Task 2 ("signed and redacted thinking replay byte for byte only to the same model"), Task 7 ("reasoning items, phase and fc_ ids replay byte for byte to the same model only"), Task 9 ("thought signatures replay byte for byte to the same model only (acceptance 2)") and the `adapter.<case>.roundtrip` rows | `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); for (api in c("anthropic-messages", "openai-responses", "openai-completions", "google-generative-ai")) { a = adapter_get(api); r = gptr_check(a); cat(api, ": ", nrow(r), " checks, ", sum(!r$ok), " failed\n", sep = "") }'` -> `anthropic-messages: 37 checks, 0 failed`, `openai-responses: 31 checks, 0 failed`, `openai-completions: 25 checks, 0 failed`, `google-generative-ai: 30 checks, 0 failed` |
| 3 | A PNG tool result is sent as a native image block to Anthropic and Responses | Task 2 ("a PNG tool result is sent as a native image block (acceptance 3)"), Task 7 ("a PNG tool result is sent as an input_image (acceptance 3)") | `Rscript --vanilla -e 'devtools::test(filter = "provider-(anthropic\|openai-responses)")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 351 ]` |
| 4 | Request bodies place breakpoints as in G4 section 3.7 and keep the frozen prefix byte-identical across turns | Task 2 ("anthropic breakpoints follow G4 section 3.7: T0 and the project block 1 h, auto tail", "the default cache policy of prompt-cache.R drives the breakpoints (acceptance 4)", "without a project block the second breakpoint moves to the T1 system block", "the frozen prefix stays byte-identical across turns and pieces are memoised"); Task 5 ("the default cache policy anchors the OpenRouter system and project blocks", "the frozen prefix stays byte-identical across turns (acceptance 4)"); Task 7 ("Responses bodies: store = false, the cache key, explicit breakpoints (G4 3.7)", "the default cache policy gives T0, T1 and project breakpoints (acceptance 4)", "the frozen prefix stays byte-identical across turns (acceptance 4)"); Task 9 ("the default cache policy gives Gemini no markers: implicit caching (acceptance 4)", "the frozen prefix stays byte-identical across turns (acceptance 4)") | row 1 command |
| 5 | With `.opts$returns`, a run with tool calls yields a typed `$value` and a transcript that still holds the tool calls (INFRA-25) | Task 2 ("provider_stream() puts the returns schema on the wire (INFRA-25)", "returns = through the run loop: a typed value and the tool calls kept (INFRA-25)": the first request of the run carries `output_config.format` and the `count` tool); Task 7 ("returns = through the run loop on Responses: instruction and validation (INFRA-25)": the first request closes with the developer instruction and sends no `tool_choice`) | row 3 command |
| 6 | End to end on the mock server (skip on CRAN): streaming, retry and abort through the reactor | Task 2 ("end to end on the mock server: streaming, retry and abort (skip on CRAN)": 3 text deltas in order, an overload before the first delta retried once with one `start`, an abort after two deltas ending `aborted` with the partial text, parallel tools); Tasks 5, 7, 9 (a Chat Completions, a Responses and a Gemini stream through P01's `chat_completions`, `openai_responses` and `gemini` scenarios) | row 1 command (with `NOT_CRAN=true`, which `devtools::test()` sets) |
| R1 | Review amendment: the adapter capability `forced_tool_choice` (`FALSE` for Anthropic 5.x) (IC-71) | Task 2 ("builtin:anthropic registers the adapter with its capabilities", "a forced tool_choice is never sent while forced_tool_choice is FALSE (IC-71)"); Task 5 ("thinking formats, tool_choice and auth headers follow the compat record") | row 1 command |
| R2 | Review amendment: `returns =` through `output_config.format` on Anthropic, else `auto` + instruction + validation (IC-71) | Task 2 ("returns = uses output_config.format and keeps the tools (IC-71, INFRA-25)", "a run of operator messages is one system message, never two in a row (07 2.3)": the closing instruction on a model without structured output); Task 5 ("returns = becomes an instruction with auto tool choice (IC-71)"); Task 7 ("reasoning effort, tool_choice, operators and returns follow 08 section 3.1"); Task 9 ("returns = becomes a user instruction; operators are user contents (IC-71)"); validation by P06's `run_returns()` in the two run tests of row 5 | row 1 command |
| R3 | Review amendment: declared `request_params` fields (IC-69) | Task 2 ("declared request params reach the body; others do not (IC-69)"); the `builtin:*` tests of Tasks 2, 5, 7 check `capabilities$request_params` | row 1 command |
| R4 | Review amendment: `check_adapter()` fails a list `tool_choice` sent while the capability is `FALSE` (IC-69, IC-71) | Task 3 ("check_adapter() fails a normaliser that throws and a forced tool_choice") | `Rscript --vanilla -e 'devtools::test(filter = "provider-anthropic")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 231 ]` |
| I8 | INFRA-08 body leg (03 section 6.18 row 08: "Anthropic -> Responses -> Gemini bodies validate against schema fixtures and contain no foreign opaque fields"; P05 checks the projected message list, P12 owns the bodies and the fixtures) | Task 7 ("a handed-off Anthropic conversation: no foreign opaque data, valid body (INFRA-08)": the `thinking_tools` turn with signed and redacted thinking and two tool calls, with its results, projected for `openai-responses` through P05's `project_messages()`, which ends with `handoff_transform()`; the body holds no signature or redacted payload, validates against `responses_body_schema()` and keeps the G4 section 3.7 key order and three explicit breakpoints); Task 9 ("Anthropic -> Responses -> Gemini: no foreign opaque data, valid body (INFRA-08)": the same transcript continued by the Responses `reasoning_tools` turn, projected for `google-generative-ai`; no signature, redacted payload, reasoning item, encrypted content, `phase` id or `thoughtSignature`; validates against `gemini_body_schema()`); both schemas are closed, and each test shows that a body carrying a signature fails them | `Rscript --vanilla -e 'devtools::test(filter = "provider-(openai-responses\|google)")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 231 ]` |
| H | House rules: no lints, ASCII-only sources, layering respected | all tasks | `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'` -> no lint printed; exit 0 (the namespace is loaded first because lintr's `object_usage_linter` resolves internal functions through `getNamespace("gptr")` and otherwise reports every internal call of an uninstalled tree: P01 decision 5, acceptance A3 and the note below it; P12 contributes no lint: the four `R/provider-*.R` files, the seven test files and the two `fixtures/sse/` scripts, which `lint_package()` lints because P01's `.lintr` excludes only `fixtures/docs`; the two top-level test helpers that call the sourced `first_message()` carry `# nolint: object_usage_linter.`); `Rscript --vanilla -e 'devtools::test(filter = "^(lint-rules\|arch-layers)$")'` (a bare `"lint\|arch"` would also select P10's `test-tool-search.R`) -> no failure that names a P12 file (P12 adds no second definition of any function name, and its only calls into other files are to L0/L1 functions: P01 `aaa-state.R`, `json-encode.R`, `json-partial.R`, `provider-events.R`, `provider-message.R`, `utils-encoding.R`, `utils-hash.R`, `utils-options.R`; P02 `ext-specs.R`; P04 `http-sse.R`; P05 `provider-registry.R`, `provider-usage.R`) |

`R CMD check` is not a P12 gate: the M2 exit check runs after P13 (05 milestones table).

---

## Self-review

### Spec coverage

| 05 P12 scope item, acceptance check or review amendment | Task |
|---|---|
| `provider-anthropic.R` (the `anthropic-messages` adapter: build, decoder, breakpoints, operator messages; architecture section 3.2) | 1 (normaliser), 2 (build, breakpoints, operator messages) |
| `provider-openai-responses.R` (stateless replay of encrypted items and `phase`) | 6, 7 |
| `provider-openai-completions.R` with the compat flags of 09 section 3 and a streaming `<think>` splitter | 4 (`compat_flags()`, `think_splitter()`, normaliser), 5 (build) |
| `provider-google.R` (thought signatures, finish reasons) | 8, 9 |
| each file registers its adapter through its own `builtin_<name>()` | 2 (`builtin_anthropic`), 5 (`builtin_openai_compat`), 7 (`builtin_openai`), 9 (`builtin_google`) |
| request bodies follow the cache plans of `prompt-cache.R` (G4 section 3.7) | 2, 5, 7, 9 (each with a test driven by the registered `default` cache policy) |
| `.opts$returns` structured output (INFRA-25) | 2, 5, 7, 9 (bodies); 2 and 7 (runs through P06) |
| wire fixtures under `tests/testthat/fixtures/sse/` | 1, 4, 6, 8 (generator and generated files) |
| gated live tests | 10 |
| INFRA-08 body leg (03 section 6.18 row 08: "fixtures P12"): Anthropic -> Responses -> Gemini bodies validate against schema fixtures and carry no foreign opaque fields | 7 (Responses body, `responses_body_schema()`), 9 (Gemini body after a Responses turn, `gemini_body_schema()`); Plan acceptance row I8 |
| 04 section 7.12 cross-plan functions `anthropic_normaliser()`, `check_adapter()` (service `check.adapter`), `compat_flags()` | 1, 3, 4 |
| Acceptance 1-6 | see Plan acceptance rows 1-6 |
| Review amendments: `forced_tool_choice` (FALSE for Anthropic 5.x); `returns =` through `output_config.format` on Anthropic, else `auto` + instruction + validation; declared `request_params`; `check_adapter()` fails a list `tool_choice` while the capability is `FALSE` (IC-69, IC-71) | 2, 5, 7, 9 (capabilities and bodies); 3 (conformance) |
| Research: 07 sections 2-5 and fact-check (tool-name regex 128 characters, mid-conversation system-message placement: one system message per operator run, Task 2; no `temperature` on 5.x models, Task 2; oauth beta, UTF-8 marking); 08 section 3 and fact-check (encrypted-reasoning backfill, `phase`, unique request ids); 09 sections 2-4 and fact-check (Gemini signatures, compat flags, header key); G4 section 3.7; 10a INFRA-02/07/08/25 | 1-9 (cited in each task's notes and file headers) |

Every acceptance check maps to named tests in the Plan acceptance table.

### Placeholder scan

The plan was searched for "TBD", "TODO", "implement later", "fill in", "appropriate error handling", "handle edge cases", "similar to Task" and "write tests for the above": none occur. Every step that changes code shows the complete code. Every function the code calls is defined in this plan or listed for an earlier plan in 04: P01 (`%||%`, `on_load`, `ext_service_set`, `ext_service_has`, `ev_new`, `block_*`, `msg_*`, `json_encode`, `json_decode`, `json_obj`, `json_verbatim`, `partial_json`, `canonical_json`, `hash_sha256`, `hash_xxh128`, `read_utf8`, `write_utf8`, `raw_to_utf8`, `gptr_has_human`, `schema_validate`; test helpers `local_gptr_options`, `local_mock_server`), P02 (`gptr_adapter`, `ext_declare_builtin`, `gptr_check`, `gptr_register`, `gptr_provider`, `gptr_tool`, `registry_get`), P04 (`sse_splitter`, `ndjson_splitter`, `reactor_http`, `reactor_task`, `reactor_pump`), P05 (`provider_get`, `adapter_get`, `model_resolve`, `provider_stream`, `usage_new`, `usage_cost`; tests: `project_messages`), P06 (`session_new`, `session_run`), P07 (the `default` `cache_policy` record). The test helpers live in `tests/testthat/fixtures/sse/replay_helpers.R` because 05 lets P12 write only the files it owns and it owns `fixtures/sse/`; each P12 test file sources it with `source(testthat::test_path("fixtures", "sse", "replay_helpers.R"), local = TRUE)`.

### Type and name consistency with 04

- `anthropic_normaliser(model, opts)`, `check_adapter(adapter, fixtures = NULL)` and `compat_flags(provider, model)` have the names, arguments and files of 04 section 7.12; the service is registered as `check.adapter` with the signature of 04 section 7.0 and owned by a built-in (IC-34).
- The built-ins are `builtin:anthropic`, `builtin:openai`, `builtin:openai-compat` and `builtin:google` (04 section 10.3) with the factories of 04 section 7.12; the adapters are `anthropic-messages`, `openai-responses`, `openai-completions` and `google-generative-ai` (04 section 8.1), built with `gptr_adapter()` as amended by IC-35.
- `build()` returns exactly the request-spec fields of 04 section 8.1 (`url`, `method`, `headers`, `body`, `stream`); normalisers expose `push`, `finish`, `fail`, `message` (and `push_parsed` for Anthropic); `capabilities` carry only the 04 section 8.1 names with values from their allowed sets.
- Events use only the INFRA-02 types and fields of 04 section 4.5 and are built with `ev_new()`; messages and blocks only through P01's constructors with the 04 section 4.1-4.2 fields; usage through P05's `usage_new()` with the 04 section 4.3 fields; stop reasons and routes from 04 section 4.2; error classes from 04 section 2.2.
- Compat fields use P05's snake_case names (P05 Task 2), plus five P12 defaults named in the Global Constraints.

### Ambiguities in 04 and deviations of dependency plans (recorded, not resolved by inventing API)

1. **P02 defines a private `check_adapter(spec, target, adapter_check)`** in `R/ext-check.R` (plan text of 2026-10-01, 11:19). 04 section 7.12 gives `check_adapter(adapter, fixtures = NULL)` to P12 in `provider-anthropic.R`. Two definitions of one name let the later-collating `provider-anthropic.R` replace P02's, and `gptr_check()` then fails with `unused argument (adapter_check)` (reproduced). This plan follows 04 and adds a precondition check to Task 3; P02 must rename its helper (for example `check_adapter_rows()`, one call in `check_spec()`). With that rename applied in the scratch build, all P12 tests and `gptr_check()` pass.
2. **How `.opts$returns` reaches `context$params` (resolved in P07).** 04 section 8.1 carries `returns` in `context$params`. An earlier P07 text set `params$returns = NULL`; P07's current `prompt_request_context()` (plan text of 2026-10-01, 11:49) reads the running call's `run$opts$returns` from the session's live run, so with P06 and P07 loaded the adapters receive the schema. The two run tests (Tasks 2 and 7) therefore assert it on the wire: Anthropic's first request carries `output_config.format`, the Responses request closes with the developer instruction. If a later P07 revision stops filling `params$returns`, those expectations fail instead of passing vacuously on P06's text validation.
3. **P01's `acc_new()` is quadratic.** `buffer$parts[[buffer$n]] = ev$delta` on an environment reached through a variable copies the whole list on every delta (measured with the P01 code of 2026-10-01: 5,000 deltas 0.14-0.16 s, 20,000 deltas 1.7-2.2 s). P05's `provider_stream()` and P06's run push every event into such an accumulator, so INFRA-23's linear decoding does not hold end to end until P01 takes the list out of the environment and clears the binding before setting an element (the form `adp_buffer_add()` uses: 20,000 appends in 0.013 s). P12's own normalisers are linear (40,000 deltas in about 1.6 s, dominated by JSON parsing; Task 1 test).
4. **`request_id` in `start` and `error` events.** `parse(model, opts)` receives no request context and the response headers stay in P05's transport, so P12's normalisers emit `request_id = NULL`. P05's `provider_stream()` knows `context$request_id` and fills it into those events and the final message (P05's `stream_request_id()`, its cross-plan consolidation row C1; an id the adapter set is kept); P06 already keys usage rows by its own `run$request_id`.
5. **Golden-event projection.** 04 section 12.3 names `ts`, `session`, `run` and `request_id` as the volatile fields. P12's projection also leaves out `preview` (throttled by wall-clock time), `agent` and `turn` (set by the run, not the adapter), the `start` event's `api`, `provider` and `model` (the fixture model), and the terminal event's `message` and `usage`, which are compared through `<case>.message.json`.
6. **The `cache` capability is per adapter, but `openai-completions` serves many hosts.** It declares `"openrouter"`, so P07's default policy anchors T0 and the project block, and the adapter writes `cache_control` markers only for providers whose compat record has `cache_control_format = "anthropic"` (OpenRouter's Anthropic and Google models); every other host ignores the anchors.
7. **Memo keys.** 04 section 8.1 describes the memo as "keyed `<entry id>|<api>|<same model>`", but projected messages carry no entry id (P05's `project_messages()` returns message records). P12 keys each serialised piece by a hash of the fields that reach the wire (role, content, api, provider, model, call ids, kind, tool declarations) plus the api, the same-model flag and the placement flags, so a rebuilt copy of an entry hits the same piece.
8. **`returns` without native structured output.** "auto + instruction + validation" leaves the instruction's position open; P12 appends it at the tail (on Anthropic models with `mid_system` a system message when it directly follows a user turn, so a trailing operator run is then sent as user text and no two system messages meet; a developer message on Responses; a user message on Chat Completions and Gemini), so every earlier element except, on Anthropic, a trailing operator run stays unchanged. The instruction sits at the tail, so the next request diverges from the previous one at the instruction's position (the cache read stops there); that cost is inherent to a tail instruction. Anthropic uses `output_config.format` only when the model record says `structured_output = TRUE`.
9. **Refusing `sk-ant-oat` subscription tokens** (architecture section 8.1) needs the key value, which only P03 and P04 may read (04 section 7.3); adapters see handles only. It belongs to P05's credential resolution or P03's registration; P12 does not implement it, and neither P03's nor P05's plan text of 2026-10-01 does (a gap reported for those owners). Resolved in P05's cross-plan consolidation (its log row C2): `provider_credential()` skips an `sk-ant-oat` value for the `anthropic` provider and, with nothing else found, signals `gptr_error_no_key` naming the subscription token; P12 still does nothing here.
10. **Fixture lookup for `gptr_check()` outside the source tree.** The service is called without `fixtures`, so `check_adapter()` looks in `fixtures/sse/<api>` under the working directory and in `tests/testthat/fixtures/sse/<api>`; an installed package ships no tests, so `gptr_check()` on a built-in adapter run from another directory reports `adapter.fixtures` as failed with a message naming the `fixtures` argument.
11. **Owner of `check.adapter`.** IC-34 makes every service owned by a built-in; the service lives in `provider-anthropic.R`, so it is owned by `builtin:anthropic`, and a `-builtin:anthropic` filter also removes fixture replay from `gptr_check()`.
12. **`thinking = "off"` on Anthropic adaptive models.** The `thinking` field is omitted (the API default is adaptive on 5.x; Sonnet 5.5's `between_tools` is not used), because the catalog clamps `off` for models that cannot disable thinking.
13. **Explicit OpenAI cache mode.** `prompt_cache_options` and explicit breakpoints apply to GPT-5.6 and later (report 08 section 2.A); P12 enables them for the provider `openai` only (`compat_flags()$explicit_cache_mode`); whether older OpenAI models reject the field is not documented (UNCERTAIN), and a provider record can switch it off through `compat`.
14. **Route of reused normalisers.** Messages get `route = "plan-cli"` for CLI model records and `"system-one"` for classifier records (the mapping P05's `stream_route()` uses), so P20's reuse of `anthropic_normaliser()` needs no patch.
15. **Classifier adapters in `gptr_check()`.** P02's `gptr_check()` calls the `check.adapter` service for every adapter spec, including P13's `typesafe-system-one` (`transport = "http_json"`, only `classify`) and any plugin classifier. Such an adapter has no stream normaliser to replay, so `check_adapter()` returns the one row `adapter.replay` (ok) for it, as for `inprocess` generators; its fixtures are P13's `fixtures/jev/`. Process adapters (P20's `cli-claude`, `cli-codex`) are replayed from `.jsonl` files only when `fixtures` points at them; `adp_replay()` passes `emit`, `signal`, `base_url` and a no-op `send`, so a P20 normaliser that needs `opts$gate` or `opts$mcp_dispatch` for a fixture must be checked through P20's own tests.

### Executed validation

All runs used `Rscript --vanilla` (R 4.4.3, macOS) in a scratch directory, never the repository; no model API was called.

- **Code blocks.** Every ```` ```r ```` block of this plan (30) was extracted to its own file and parsed with `Rscript --vanilla -e 'invisible(parse(file = "<f>"))'`: all parse. `getParseData()` finds no `LEFT_ASSIGN` token in any block (no `<-` and no `<<-`); no block contains `%>%` or `:::`; the plan file is ASCII only (non-ASCII test text is written as backslash-u escapes inside R strings).
- **The plan builds and passes.** The R and test files were extracted mechanically from this plan's `Create`/`Append to` blocks into a scratch package together with the code of the P01-P07 plan files as they stood on 2026-10-01 (11:19-11:30). Two fixes to the dependency text were needed, neither in P12: P06's "replace ... with ..." fragment for `run_start()` was applied by hand, and P02's private helper was renamed `check_adapter_rows()` (ambiguity 1). The extracted `R/provider-*.R` files are byte-identical to the files the red/green runs used. `make_fixtures.R` wrote 62 fixture files (18 + 13 + 15 + 16), byte-identical on a rerun.
- **Red and green.** For each task, the red run (the task's tests with the previous tasks' code) and the green run gave exactly the summaries written in Steps 2 and 4 (with `NOT_CRAN=true`, as `devtools::test()` sets it). Final runs (re-run by the cross-plan consolidation of 2026-10-01 against the P01-P07 plan texts used by the review, with P05's current `provider-registry.R`, `provider-transform.R`, `provider-usage.R` and `catalog-models.R`): `provider-(anthropic|openai|google)` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 604 ]`; without `NOT_CRAN` -> `[ FAIL 0 | WARN 0 | SKIP 5 | PASS 580 ]`; also under `LC_ALL=C`; `^live-(anthropic|openai|google)$` -> `[ FAIL 0 | WARN 0 | SKIP 3 | PASS 0 ]`; per file 231, 142, 120 and 111 passes; `gptr_check()` on the four adapters from the package root: 37, 31, 25 and 30 checks, none failed. The mock-server tests started P01's base-R server through processx and passed (stream, overload retry, abort, parallel tools, and the Chat Completions, Responses and Gemini scenarios).
- **Lint and layering.** With P01's `.lintr` (all default linters, including `indentation_linter` and `object_usage_linter`) and the namespace loaded first (`pkgload::load_all(quiet = TRUE)`, P01 A3), `lintr::lint_package()` reports 0 lints in the four R files, the seven test files and the two fixture scripts (the remaining lints of the scratch package were all in P06/P07 files of the older plan snapshot it holds, not in P12 files); `lintr::lint()` over the same 13 files: 0 lints. The consolidation fixed the 42 indentation and 2 object-usage lints in the test code that the earlier run (indentation and object-usage linters off) had not seen; see the consolidation log. P01's `lint_scan()` (the rules of `test-lint-rules.R`) over the four R files: 0 hits. P01's `helper-arch.R` function map: no P12 function name is defined twice, and the 355 calls from P12 files into other files break no layer rule.
- **Linear decoding.** The Anthropic normaliser consumed 5,000, 20,000 and 40,000 text deltas in 0.20, 0.76 and 1.6 s (linear; JSON parsing dominates). The earlier buffer form `b$v[[n]] = x` measured 0.32 s and 2.45 s for 5,000 and 20,000 deltas (quadratic), which is why `adp_buffer_add()` takes the list out of the environment first.
- **Not executed here:** the live tests (paid requests; `GPTR_LIVE_TESTS` was not set), `R CMD check` (not a P12 gate) and Windows. The P12 test files were run under `LC_ALL=C` in the scratch package (all pass), not through the CI job itself.

---

## Plan review log

Adversarial review of 2026-10-01. Method: every `R/`, test and fixture-script block of this plan was extracted task by task into a scratch package with the P01-P07 plan code of that day (P07 at 11:49; the two dependency fixes of the "Executed validation" list applied), and each task's red phase (its tests and fixtures with the previous tasks' code) and green phase were run with `NOT_CRAN=true`. The original text reproduced every summary it states (red 12/1, 19/95, 6/191, 11/1, 11/89, 6/1, 11/49, 6/1, 9/56, 3/0; green 95, 190, 213, 89, 142, 49, 105, 56, 97, skip 3) and the `gptr_check()` counts 37/31/25/30, so the review concentrated on contract, research and test-design defects that the plan's own tests could not reveal. After the fixes below the red/green runs give the summaries now written in Steps 2 and 4 (Task 1: 13/1 and 99; Task 2: 20/99 and 204; Task 3: 6/205 and 231; Task 7: 11/49 and 108; the others unchanged), the combined filter gives `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 578 ]` (`SKIP 5 | PASS 554` without `NOT_CRAN`, also under `LC_ALL=C`), all 29 R blocks parse, no block has a `LEFT_ASSIGN` token, `%>%` or `:::`, the plan file is ASCII, P01's `lint_scan()` finds nothing in the four R files, no line exceeds 100 characters, every top-level function carries an `@noRd` roxygen block, and P01's `helper-arch.R` finds no layering violation and no duplicate name from a P12 file.

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | major | Task 3 `check_adapter()` | P02's `gptr_check()` calls the `check.adapter` service for every adapter spec, but a classifier adapter (P13's `typesafe-system-one`: `transport = "http_json"`, only `classify`) has no `parse`: without fixtures it got `adapter.fixtures` FALSE, with fixtures `adapter$parse` failed ("attempt to apply non-function", reproduced), so `gptr_check()` failed every classifier adapter | applied | adapters without a stream normaliser (`inprocess`, or no top-level `parse`) return the one row `adapter.replay` (ok); test "check_adapter() reports missing fixtures and skips inprocess and classifier adapters" builds an IC-35 classifier adapter and checks `check_adapter()` and `gptr_check()`; Interfaces text and ambiguity 15 added |
| 2 | major | Task 2 `anthropic_elements()`, `anthropic_operator()`, `anthropic_build()` | Report 07 section 2.3 (verification row 14): a mid-conversation system message must follow a user message and be last or followed by an assistant turn. A run of several operator messages (P07 flushes each queued operator as its own message) was sent as consecutive system messages, and a non-native `returns` instruction could follow a system message as another system message or as a user message | applied | a run of operator messages is rendered as ONE message (system or user); a trailing run is user text when a `returns` instruction closes the request, and the instruction is a system message only right after a user turn; new test "a run of operator messages is one system message, never two in a row (07 2.3)"; body-rule paragraph, Global Constraints and ambiguity 8 updated |
| 3 | major | Tasks 2 and 7 INFRA-25 run tests; self-review ambiguity 2 | The run tests checked only `$value` and the roles, so the review amendment "returns = uses output_config.format on Anthropic" was never proven through a run, and ambiguity 2 told implementers that P07 drops `params$returns` and P06 must change; P07's current `prompt_request_context()` passes `run$opts$returns` (verified in scratch: the first run request carries `output_config.format`, the Responses request the developer instruction) | applied | both run tests now assert the schema on the wire (and the `count` tool declared, no `tool_choice` on Responses); ambiguity 2 rewritten as resolved in P07, with the reason the expectations guard against a regression |
| 4 | major | Task 10 Steps 2 and 4; Plan acceptance row 1 | `devtools::test(filter = "live")` also selects P06's `test-session-live.R` (testthat matches the file name without `test-`), so the stated `[ FAIL 0 \| WARN 0 \| SKIP 3 \| PASS 0 ]` cannot be the result in a repository holding P06 (and later P13's `test-live-jev.R`) | applied | the plan's commands use `filter = "^live-(anthropic\|openai\|google)$"`; the maintainer's opt-in run uses the same filter, with a note on the conventions' broader filter; a Global Constraints line explains the filters; row H's `"lint\|arch"` (which also matches P10's `test-tool-search.R`) became `"^(lint-rules\|arch-layers)$"` |
| 5 | minor | Task 2 `anthropic_build()` | Report 07 section 2.3: "non-default values are 400 on all 5.x models"; `temperature` was sent to adaptive (5.x) models whenever thinking was off | applied | `temperature` only for models without adaptive thinking and without a thinking configuration; expectations added to "adaptive models get adaptive thinking and effort; budget models an enabled budget"; Global Constraints line added |
| 6 | minor | Task 1 `adp_normaliser()` | 04 section 8.1: "Normalisers never signal R conditions after `start`", but `fail(cnd)` and `message()` were unguarded (a malformed condition made `fail()` throw) | applied | `fail()` turns an internal error into the one terminal `error` event (class `internal`), `message()` falls back to an empty error message; new test "fail() and message() never signal, even for a malformed condition (04 section 8.1)" |
| 7 | minor | Task 3 test "check_adapter() fails a normaliser that throws and a forced tool_choice" | `expect_false(any(res$ok[...]))` passes vacuously when no `.no_condition` row exists (`any(logical(0))` is `FALSE`), for example when the fixture directory is not found | applied | the test first asserts the six `.no_condition` rows |
| 8 | minor | Task 2 `anthropic_tool_result()` | whitespace-only text blocks were sent inside `tool_result` content, unlike the rule `anthropic_user()` and `anthropic_assistant()` apply | applied | `nzchar(trimws(b$text))`; the `(see attached image)` lead text still covers image-only results |
| 9 | minor | Tasks 2, 5, 7, 9 mock-server tests | conventions section 7: "Tests that start processes or servers call `skip_on_cran()`"; the tests relied on `local_mock_server()` skipping internally | applied | each mock-server test starts with `skip_on_cran()` (no count changes: the helper skipped at the same point) |
| 10 | minor | Global Constraints | conventions section 10 requires the harness attribution line at the end of every commit message; the constraint line said only "one commit per task" | applied | the line now names the attribution line |
| 11 | minor | Self-review ambiguity 9 | the `sk-ant-oat` refusal of architecture section 8.1 is implemented by no plan (P03 and P05 texts checked), which the note did not say | applied | the note records the gap for P03/P05 |
| 12 | minor | Steps 2 and 4 of Tasks 1, 2, 3, 7; Plan acceptance rows 1, 3, R4; Executed validation | the expected summaries changed with the added expectations | applied | recounted by running every red and green phase (numbers above) |
| 13 | minor | Task 2 opaque server-tool blocks | the `content_block` of a server-tool block is stored re-serialised by `json_encode()`, not as the wire substring (INFRA-07 says opaque data is stored byte for byte) | rejected | the contract's byte-for-byte list is signatures, encrypted reasoning, `phase` and thought signatures, which are kept verbatim; the block's JSON arrives inside the event's `data` and only a JSON slicer could cut it out; the re-serialised object is semantically identical, its `encrypted_content` strings are byte-identical and the `adapter.<case>.roundtrip` rows prove a stable re-send |
| 14 | minor | Self-review ambiguity 10 | `gptr_check()` on a built-in adapter fails outside the source tree because the fixtures are not installed | rejected | 04 section 12.4 places the fixtures under `tests/testthat/fixtures/sse/` and 04 section 7.12 defines the lookup; P12 cannot ship them elsewhere; the failure row names the `fixtures` argument |
| 15 | minor | Task 3 precondition on P02 | the precondition stops the implementer when P02's private `check_adapter()` still exists | rejected | 04 section 7.12 gives the name to P12 and P02's file is not P12's to edit; the grep check with the exact rename (`check_adapter_rows()`) is the safest instruction (the clash was reproduced: `unused argument (adapter_check)`) |
| 16 | minor | Task 2 effort placement | G4 section 3.7's table moves Anthropic effort into a mid-conversation `system` `output_config` (beta `mid-conversation-output-config-2026-07-01`) | rejected | the effort is constant within a session (it follows the frozen thinking level), so the top-level `output_config.effort` never changes between requests and never breaks the cache; the per-message form needs an extra beta and belongs with a per-turn effort feature |
| 17 | minor | Task 5 thinking formats | DeepSeek accepts the efforts `low`, `high` and `max` (report 09 verification row 43); `medium` would be sent verbatim | rejected | the model record's `thinking` is the level P05's catalog clamps to the model's `thinking_levels` (04 section 4.9), so a level the model lacks is not requested; a per-model effort map is a catalog field 04 does not define |
| 18 | minor | Task 5 OpenRouter session affinity and system role | G4 section 3.7's table names `session_id` and a `system` role, the plan sends `x-session-id` and `developer` for reasoning models | rejected | G4 section 2.6 accepts `session_id` in the body or `x-session-id`, which is Pi's `openrouter` affinity format (report 09 section 2.3); the developer role follows Pi's `supportsDeveloperRole` rule, which the OpenRouter compat record controls |

---

## Cross-plan consolidation log

Cross-plan consolidation of 2026-10-01. Each issue was checked against 04, 05, 03 and the related plans' current text. Validation ran in a scratch package (`work/consolidate/P12/pkg`: the P01-P07 plan code used by the review, with P05's current `provider-registry.R`, `provider-transform.R`, `provider-usage.R` and `catalog-models.R`, and this plan's R, test and fixture-script blocks extracted mechanically): every task's red and green phase gives the summaries written in Steps 2 and 4 (Tasks 1-6, 8 and 10 unchanged; Task 7 red `FAIL 12 | PASS 50`, green `PASS 120`; Task 9 red `FAIL 10 | PASS 57`, green `PASS 111`), the combined filter gives `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 604 ]` (`SKIP 5 | PASS 580` without `NOT_CRAN`, also under `LC_ALL=C`), `gptr_check()` still gives 37, 31, 25 and 30 checks with none failed, all 30 `r` blocks parse with no left-arrow token, `%>%` or `:::`, no code line exceeds 100 characters, and the plan file is ASCII.

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| C1 | obligations | minor | Plan acceptance row H | applied | Valid: P01 decision 5 and its A3 note; a bare `lintr::lint_package()` on the uninstalled tree reports every internal call through `object_usage_linter`, and P12's own lint run had that linter (and `indentation_linter`) turned off. Row H now runs `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'` and expects no lint and exit 0 (the form of P01 A3, P02, P03, P04, P05, P07, P09 and P22). Running it showed that the test code did not meet it: 42 `indentation_linter` lints (multi-line `paste0(` calls whose closing parentheses shared the last argument's line, which lintr's tidy style reads as a hanging indent, in Tasks 1, 2, 6, 7, 8 and 10; off-by-one continuation lines in `responses_sse_tool()`/`responses_sse_text()`; `body_1h` in Task 2; the nested `properties = list(` expectation in Task 7) and 2 `object_usage_linter` lints (`anthropic_turn2()` and `completions_turn2()` call `first_message()`, defined in the sourced `replay_helpers.R`, which lintr cannot see). The closing parentheses now stand on their own line, the alignments were corrected, the Task 7 expectation builds `read_params` first, and the two helpers call `first_message()` on a line with `# nolint: object_usage_linter.` (P02's precedent). No test changed meaning: every red and green summary is unchanged. With P01's `.lintr` and the namespace loaded, the four R files, seven test files and two fixture scripts give 0 lints; Executed validation updated |
| C2 | trace | minor | Tasks 7 and 9; Plan acceptance | applied | Valid: 03 section 6.18 row 08 makes INFRA-08's acceptance "Anthropic -> Responses -> Gemini bodies validate against schema fixtures and contain no foreign opaque fields (... P05, fixtures P12)"; P05 (acceptance 3) checks only the projected message list, and P12's replay tests were same-model only, so no plan built a foreign body from an Anthropic-origin conversation. Task 7 appends to `replay_helpers.R` `handoff_entries()` (transcript entries of 04 section 4.6 holding the `thinking_tools` fixture turn: signed and redacted thinking, two parallel tool calls, and both results; plus the opaque strings of its assistant messages), `wire_object()` and `responses_body_schema()` (a closed schema fixture of the Responses body for P01's `schema_validate()`), and adds the test "a handed-off Anthropic conversation: no foreign opaque data, valid body (INFRA-08)": the entries go through P05's `project_messages()` (which ends with `handoff_transform()`, as `request_build()` runs it) for `openai/gpt-6-sol`, `responses_build()` builds the body, and the test asserts that neither the signature nor the redacted payload appears, that the body validates, the G4 section 3.7 key order and three explicit breakpoints, the item kinds, plain `call_` ids without `fc_` item ids, and that a signature added to an item fails the schema (12 expectations). Task 9 appends `gemini_body_schema()` and adds "Anthropic -> Responses -> Gemini: no foreign opaque data, valid body (INFRA-08)": the same transcript continued by the Responses `reasoning_tools` turn and its result, projected for `google/gemini-3.8-flash`; no Anthropic signature or redacted payload, no reasoning item, encrypted content, message id or `thoughtSignature`; the body validates, keeps the key order, its call and response ids pair up, foreign thinking is plain text, and a signature added to a part fails the schema (14 expectations). Interfaces, File Structure, Spec coverage, Placeholder scan and the expected summaries (Task 7: red 12/50, green 120; Task 9: red 10/57, green 111; rows 1 and 3: 604 and 351) updated; new Plan acceptance row I8. A mutation run (identity `handoff_transform()` and an adapter that treats every turn as the same model) fails both tests |
| C3 | trace | minor | Plan acceptance row H | applied (same change as C1) | Duplicate of C1; the one replacement and the lint fixes cover both |

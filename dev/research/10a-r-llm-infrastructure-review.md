# Track 10a — The R LLM packages' infrastructure, reviewed against agent requirements, and what gptr's own layer must do

Date: 2026-09-29. Author: research agent, track 10a. Audience: gptr architects.

Scope. This is a source-level review of the sending/receiving *infrastructure* of the R LLM packages:
transport, streaming, interrupts, retries, the message and tool-call model, the agent loop, state,
concurrency, the evaluation environment and extensibility. Each is judged against gptr's agent
requirements (REQ-01..REQ-40 in `dev/spec/00-vision-brief.md`; settled decisions S-1..S-10 in
`dev/spec/01-decision-register.md`). REQ-40 / S-10 already settle that gptr builds its own layer and
depends on none of these packages. This report supplies the evidence for that decision, lists what gptr
should borrow (with attribution), and turns the gaps into testable requirements INFRA-01..INFRA-28.

It builds on track 10 (`dev/research/10-r-llm-ecosystem-prior-art.md`, the landscape and the ellmer-bridge
prototypes) and refers to 02 (agent loop, interrupts), 03 (provider layer), 07/08/09 (wire formats),
12 (evaluation, copy safety), 15 (concurrency), 18 (console) and 21 (hot paths) for how to build each part in R.

Evidence labels: **VERIFIED** = I read the cited source lines, or ran the command and show its output here.
**LIKELY** = strong inference from verified facts. **UNCERTAIN** = not confirmed.

Paths. `$W` = `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/10a`
(scripts, logs, outputs). `$S` = `$W/src` (CRAN sources extracted from MD5-verified tarballs, section 2.1).
`$T10R` = `.../scratchpad/work/track10/rlib` (track 10's private library: ellmer 0.5.0, httr2 1.3.0, btw 1.5.0,
mcptools 1.0.3). Source citations are `package/R/file.R:line` relative to `$S`. The system library holds
ellmer 0.4.0 with httr2 1.2.2 and curl 7.0.0. All experiments use R 4.4.3, `Rscript --vanilla`, macOS arm64.
Load averages were 6–22 during the runs because other research tracks shared the machine, so treat timings as
relative. No paid API call was made. All LLM traffic went to a local base-R mock of the Anthropic Messages API
(`$W/mock_anthropic.R`, Appendix A.1). Nothing was installed into the user library, and nothing in the gptr
repository was changed except this file.

The scripts are reproduced in full in Appendix A, because the scratch directory is session scoped.

---

## 1. Executive summary

1. **Verdict.** No R package provides an agent-grade send/receive layer. The strongest, **ellmer**
   (Posit), is a well-engineered *chat client*. Its transport, message model and loop make choices that
   are sound for chat and wrong for an agent that runs for many turns, streams, calls tools, is
   interrupted, is steered, and hands off between providers. The other packages are either built on
   ellmer (btw, chattr, mall, mcptools; tidyllm optionally), or thinner and weaker in the same places
   (tidyllm, llm.api/corteza, aisdk, agenticr, rollama, gptstudio, openai). This confirms S-10. The
   decisive reasons are behavioural and verified below. Dependency size and API churn (track 10) are
   secondary. VERIFIED (sections 3–10, experiments E1–E16).
2. **The synchronous streaming path is not incremental.** Against a mock that emits one SSE event every
   0.25 s, ellmer 0.5.0 + httr2 1.3.0 (current CRAN) delivered its **first** `$stream()` delta at
   4.72 s, after the whole stream had arrived. A `curl::multi_run()` loop saw the first event at 0.24 s.
   With httr2 1.2.2 the deltas arrive in ~1 KB bursts (2.12 s, then 4.19 s). The cause is httr2's
   blocking connection read. In 1.3.0 it asks for `stream_chunk_bytes = 65536`, and a blocking curl
   read returns only when that many bytes have arrived or the stream ends. `$chat(echo = "output")`,
   `$stream()` and `live_console()` all use this path. tidyllm, aisdk and rollama call the same blocking
   `req_perform_connection()`. ellmer's async path (`later_fd`) is incremental once the body starts, but it
   needs promises + coro + later and is not what the console uses. It also blocks the whole R session until
   the response headers arrive: during a 3 s time-to-first-token, a `later` callback scheduled at 0.5 s ran
   at 3.35 s (Verification log, V-8). VERIFIED (E1, E2, both re-run in the Verification log; mechanism for
   1.2.2 also in report 09 §2.10/§5.2). That real HTTPS/HTTP-2 providers behave the same is LIKELY, not
   tested live.
3. **ellmer 0.5.0's cost of consuming a stream grows quadratically with the number of deltas** (each
   delta costs time proportional to the deltas already received). Consuming a 2,000-delta stream took
   **14.2–18.0 s** with ellmer 0.5.0 (11.8 s in the verification re-run), against 1.35 s with 0.4.0
   (0.83 s in the re-run). Reading and parsing the same stream with httr2 alone
   took 0.39–0.45 s. The likely cause: every delta is appended to the partial turn with an S7 property
   assignment (`ellmer/R/chat.R:1403-1409`), and the `prop_list_of()` validator re-checks every element on
   each assignment (`ellmer/R/utils-S7.R:119-131`). A micro-benchmark of that exact pattern took 8.5 s
   for 2,000 appends; the re-run gave 0.15 / 0.54 / 2.26 / 9.05 s for 250 / 500 / 1,000 / 2,000 appends,
   i.e. about 4× per doubling. Timing VERIFIED (E14, re-run). Attribution LIKELY.
4. **Interrupts escape, and they lose or misreport work.** With SIGINT during streaming, during
   time-to-first-token, or during a running tool, the `interrupt` condition always reaches top level.
   Nothing lets the caller resume or steer. In 0.5.0 the partial assistant turn was **empty** although the
   server had already written at least three text deltas. Those deltas had not yet reached R, because the
   blocking read had not returned (finding 2), so ellmer did not discard data it had received. When deltas
   had been delivered (E5), the partial kept them. 0.4.0 drops the whole exchange. The next request
   replays the empty partial as the assistant text **"[empty string]"**. When the interrupt hit a tool
   2.3 s into a 4 s run, the next call told the model **"Chat ended before the tool could be invoked."**,
   which is false, since the tool ran and may have changed the user's objects. The interrupt was observed
   1.2–1.4 s after SIGINT on 0.5.0/httr2 1.3.0, against 0.16 s on 0.4.0/httr2 1.2.2 (cause UNCERTAIN).
   VERIFIED (E3, wire bodies logged by the mock).
5. **Failure paths corrupt state or abort the run.** All VERIFIED.
   - An HTTP 401 in streaming mode leaves an empty `AssistantPartialTurn` with reason "interrupted" in the history (E7).
   - An Anthropic `redacted_thinking` block aborts the chat with ellmer's own "internal error" on 0.4.0 and 0.5.0 (E6). The value mode loses the entire turn.
   - A mid-stream `overloaded_error` makes ellmer `Sys.sleep()` and then fail with "Connection closed unexpectedly". 0.4.0 fails with "argument is of length zero" (E5).
   - A tool call truncated by `max_tokens` aborts with jsonlite's "parse error: premature EOF" (E10).
   - The default `req_timeout(300)` is a *total* transfer timeout. With the option at 1.5 s it killed a stream that was actively delivering bytes (E4).
6. **The message model cannot carry what agents need.**
   - An `AssistantTurn` has no provider, model or API field (`ellmer/R/turns.R:129-150`). It keeps only the raw response in `@json`, which usually includes the model name, and replay never consults it. So a turn has no normalised record of which provider produced its opaque replay data.
   - Cross-provider replay emits invalid wire items. An Anthropic thinking signature becomes a bare `{"signature":"SIG-abc123=="}` input item for OpenAI. An OpenAI reasoning item becomes `"signature":{}` for Anthropic, and its `encrypted_content` is lost (E12).
   - Tool results are sent as strings. Images are "unrolled" into extra user content (`ellmer/R/chat-tools-content.R:1-73`), although Anthropic and OpenAI now accept images inside tool results (report 07 §2.5; 08 §2.A).
   - The system prompt is one string (`ellmer/R/chat.R:165-181`).

   VERIFIED.
7. **Tool arguments are not validated.** A missing *required* argument reaches the R function as
   `NA_character_`. `"three"` passes for an `type_integer()` argument, and an array passes for a string. Only
   extra arguments are rejected (E9, both versions). tidyllm runs tools with a bare `do.call()` in its
   chat-completions, Claude, Gemini and OpenAI Responses methods, so a tool error aborts the chat (only the
   Ollama method wraps the call in `tryCatch()`, `tidyllm/R/api_ollama.R:181-190`). It also drops the result
   of an unparseable or unknown call, leaving an orphaned call id
   (`tidyllm/R/api_chat_completions.R:171-221`). llm.api never sets `is_error`. VERIFIED.
8. **Nobody owns a steerable loop.** ellmer's `while` loop has no round limit (`ellmer/R/chat.R:781-839`) and
   runs tools one after another in `$chat()` (E11). It has no steering or follow-up queue. Injecting a
   steering message through the 0.5.0 `on_request_start` + `$set_turns()` hooks puts a user message
   *between* the `tool_use` turn and its `tool_result`, a wire order the Anthropic API forbids (E11;
   report 07 §2.5). None of the main packages has a steering feature: a case-insensitive grep for "steer" over
13 of them finds only an unrelated comment in `mcptools/R/session.R:182`. VERIFIED.
9. **Sessions.** No package has an append-only message tree with fork and resume.
   - ellmer keeps a mutable in-memory list. `$clone()` is shallow and shares the callback managers (E13).
   - tidyllm's history keeps only the final assistant text of a tool loop (`tidyllm/R/chat_pipeline.R:141-188`).
   - aisdk has an append-only console event log with named branches. It lives under `getwd()/.aisdk/sessions` and uses `stats::runif()` for ids, which consumes the user's RNG stream (`aisdk/R/session_event_store.R:23-58, 138-156`).
   - corteza appends JSONL (v2, flat) through llm.api.

   VERIFIED.
10. **Process-global state rules out many concurrent agents in one session.**
    - ellmer's `token_usage()` merged two independent chats into one row, 200/40 tokens (E13). This is by design, as a process-wide summary by provider and model, and per-chat usage is still available from `$get_tokens()`. What is missing is attribution to agent and route, and the summary is mutable global state. Tool context is a package-level stack (`ellmer/R/tool-context.R:71-136`).
    - chattr (`ch_env`), rollama (`the$prompts`), mall (`.env_llm`) and btw's sub-agent registry (`.btw_subagent_sessions`) each keep one global conversation or registry.
    - `parallel_chat()` runs lock-step rounds, does not stream, runs tools sequentially, and suffers curl's PIPEWAIT stall on HTTP/1.1 (report 15 §2.2).

    VERIFIED.
11. **The evaluation environment is hard-coded, or not the caller's.**
    - btw evaluates model code in `global_env()` (`btw/R/tool-run.R:123, 232-238`) with no timeout.
    - agenticr uses `eval(expr, envir = .GlobalEnv)` (`agenticr/R/tools.R:563-565`).
    - corteza evaluates in `globalenv()` and writes hidden `.h_NNN` handles into it, accepting the R CMD check NOTE (`corteza/R/handles.R:135-160`).
    - aisdk evaluates in-process, but in its own environments: a `ChatSession` environment (default `new.env(parent = globalenv())`, or one the user supplies, into which aisdk also writes hidden bindings such as `.capability_models`; `aisdk/R/session.R:114-124`), `SharedSession$execute_code()` (`aisdk/R/shared_session.R:199-207`) and a `SandboxManager` child environment (`aisdk/R/sandbox.R:59-60, 158-170`). Its `r_eval` introspection tool runs in a `callr` subprocess.
    - chattr `mget()`s every global object to find data frames (`chattr/R/ch-context.R:59-62`), which forces promises (report 12 §C1).

    VERIFIED.
12. **System 1, subscription CLIs, and cost are missing or weak.** Nobody integrates System 1 or returns
    probabilities. mall returns factors and coerces invalid answers to `NA` (`mall/R/m-vec-prompt.R:33-55`),
    which breaks `if()`. The only CLI "provider" (ravel) blocks on `system2()`, flattens the whole
    conversation into one prompt and runs `--ephemeral` (`ravel/R/providers_openai.R:222-245`). llm.api's
    Claude-plan OAuth conflicts with Anthropic's terms (track 10, item 12). Token accounting is three
    numbers (input, output, cached input) in ellmer. Only llm.api splits 5-minute and 1-hour
    cache writes in its cost (grep for `ephemeral_1h|write_1h` over all 24 extracted packages). ellmer can
    request a 1-hour cache (`chat_anthropic(cache = "1h")`, `provider-claude.R:85`), but it prices every
    cache write at 1.25× input (`provider-claude.R:536-540`). VERIFIED.
13. **Retries do not cap Retry-After and do not cover mid-stream failures.** httr2's `retry_after()` passes
    the server value through with no cap (printed source). ellmer adds `max_tries = 3` and no
    `max_seconds`. aisdk's own loop sleeps `retry-after(-ms)` unbounded (`aisdk/R/utils_http.R:612-633`).
    ellmer, tidyllm and llm.api never retry a request that fails after streaming has begun. aisdk re-runs the
    whole stream attempt on transport errors (`aisdk/R/provider_anthropic.R:563-590`), with no record of the
    deltas it has already passed to its callback; whether duplicates then reach the user is UNCERTAIN.
    VERIFIED (E8 plus source).
14. **What they get right, and gptr should borrow (with attribution), section 15:**
    - ellmer: credentials as zero-argument functions plus redacted headers; the partial-turn-with-reason
      idea; the cancellation-token idea; errors turned into tool results; a classed `tool_reject()`;
      MCP-style `tool_annotations()`; the `type_*()` vocabulary; a litellm-derived price table with a
      `schema_version`; OTel spans; resumable batch state; `store = FALSE` plus encrypted reasoning.
    - tidyllm 0.6.0: a single stream pump (transport / parse / sink), idle-not-total deadlines, and
      `send_chat()` job handles.
    - btw: small tool texts, a cwd restriction, hash-anchored edits, and sub-agent session ids.
    - mcptools: servicing the live session when idle, and MAC-sealed IPC.
    - corteza: interrupted-tool-history repair with an honest marker.
    - llm.api: a history callback after every message, and cache TTLs in cost.
    - aisdk: layered timeouts, `retry-after-ms`, and a branch-aware append-only log.
15. **Result: 28 requirements, INFRA-01..INFRA-28 (section 14).** Each cites the limitation it answers and
    the report that shows how to build it in R. The core is:
    - one curl-multi reactor with a normalised event stream;
    - interrupt-safe streaming with resume, steer and abort;
    - a provider-neutral message model with provenance and byte-exact opaque replay data, plus a hand-off transform;
    - a never-throw, schema-validating tool dispatcher with permission hooks;
    - a gptr-owned loop with steering and follow-up queues and `max_turns`;
    - an append-only JSONL tree store;
    - no package-global run state;
    - System 1 and subscription CLIs as first-class provider kinds;
    - per-request usage and cost attributed to agent, provider and route;
    - bounded retries that honour Retry-After;
    - a fake provider, a mock SSE server and wire fixtures for tests.

---

## 2. Method

### 2.1 Evidence base (VERIFIED, `$W/md5check.R`, output `$W/md5check.out`)

Track 10's 37 CRAN tarballs (`track10/src/`) were re-checked against two independent downloads of the CRAN
package database. Both were taken 2026-09-29/30: track 10's `cran_db2.rds` and its verifier's `cran_db_v10.rds`.
Then they were extracted afresh into `$S`. Output, abridged:

```text
       pkg     ver db1_ver  ok1 db2_ver  ok2
    ellmer   0.5.0   0.5.0 TRUE   0.5.0 TRUE
   tidyllm   0.6.0   0.6.0 TRUE   0.6.0 TRUE
    chattr   0.3.1   0.3.1 TRUE   0.3.1 TRUE
 gptstudio   0.4.0   0.4.0 TRUE   0.4.0 TRUE
      mall   0.2.0   0.2.0 TRUE   0.2.0 TRUE
    openai   0.4.1   0.4.1 TRUE   0.4.1 TRUE
   rollama   0.3.1   0.3.1 TRUE   0.3.1 TRUE
       btw   1.5.0   1.5.0 TRUE   1.5.0 TRUE
  mcptools   1.0.3   1.0.3 TRUE   1.0.3 TRUE
   corteza   0.7.1   0.7.1 TRUE   0.7.1 TRUE
     aisdk  1.4.12  1.4.12 TRUE  1.4.12 TRUE
  agenticr   0.3.3   0.3.3 TRUE   0.3.3 TRUE
   llm.api   0.1.9   0.1.9 TRUE   0.1.9 TRUE
     ravel   0.1.4   0.1.4 TRUE   0.1.4 TRUE
 (… 23 more rows, all TRUE)
all ok: TRUE
db1 max pub: 2026-09-30 00:00:07 UTC  db2 max pub: 2026-09-30 00:00:07 UTC
```

Size of the reviewed sources (lines of R, `wc -l R/*.R`):

| Package | Lines |
|---|---|
| aisdk | 42,307 |
| btw | 21,677 |
| corteza | 20,290 |
| ellmer | 20,255 |
| tidyllm | 16,099 |
| mcptools | 5,061 |
| agenticr | 4,581 |
| gptstudio | 4,413 |
| llm.api | 3,554 |
| openai | 3,461 |
| chattr | 1,963 |
| mall | 1,546 |
| rollama | 523, plus `.r` files |

Runtime: ellmer 0.4.0 (system library, httr2 1.2.2) and ellmer 0.5.0 (`$T10R`, httr2 1.3.0), with curl 7.0.0 in both.

### 2.2 The agent yardstick

Every package is reviewed on the same nine questions the task sets. The agent requirements behind them:

| Dimension | What an agent harness needs (source) |
|---|---|
| 1 Send/receive | Incremental deltas; cancellation at any phase; idle timeouts, not total ones; bounded retries (REQ-11, REQ-38; reports 02, 03, 15) |
| 2 Message model | Thinking plus signatures, redacted or encrypted reasoning, images in tool results, parallel tool calls, steering, system-prompt sections, provenance for hand-off (REQ-11, REQ-14, REQ-31) |
| 3 Loop | Turn control, never-throw tools, `max_turns`, approval, abort, steering, follow-ups (REQ-17, REQ-18, REQ-36, REQ-37, REQ-38) |
| 4 State | Session object for the native pipe; append-only transcript; resume; fork (REQ-18, REQ-24, REQ-25; D-05, D-09) |
| 5 Concurrency | Many agents in one session; workers; CLI agents (REQ-32, REQ-33, REQ-34; D-12, D-13) |
| 6 Evaluation | Caller environment; copy safety; timeouts (REQ-22; D-04; report 12) |
| 7 Extensibility | Tools, hooks and providers through a stable API (REQ-29, REQ-30) |
| 8 Borrow | Designs to port, with attribution (S-10) |
| 9 Unsuitable | Concrete, evidenced reasons |

### 2.3 Experiments (all in `$W`; scripts in Appendix A; raw outputs in section 4)

| ID | Question | Script | Versions |
|---|---|---|---|
| E0 | Are the tarballs genuine? | `md5check.R` | – |
| E1 | When do streamed deltas reach R code (ellmer sync / async vs curl multi)? | `stream_timing.R`, `run_timing.sh` | 0.4.0, 0.5.0; identity and chunked bodies |
| E2 | Is the batching httr2's own (blocking vs non-blocking)? | `httr2_timing.R` | httr2 1.2.2, 1.3.0 |
| E3 | What does Ctrl-C do during the body, during TTFT, and during a tool? What is replayed next? | `child_ellmer.R`, `driver_ellmer.R` | both |
| E4 | Is the ellmer timeout total or idle? | same (`timeout`) | both |
| E5 | Mid-stream `overloaded_error` | same (`overload`) | both |
| E6 | `redacted_thinking` block | same (`redacted_*`) | both |
| E7 | HTTP 401 in stream vs value mode | same (`e401_*`) | both |
| E8 | 429 with `retry-after` | same (`r429`) | 0.5.0 |
| E9 | Tool-argument validation | `tool_validation.R` | both |
| E10 | Tool call truncated by `max_tokens` | same (`trunc`) | both |
| E11 | Parallel tool calls; steering hack wire order | same (`par`, `steer_hack`) | both / 0.5.0 |
| E12 | Cross-provider replay of reasoning | same (`handoff`) | both |
| E13 | Global token accounting; clone semantics | same (`tokens_global`, `clone`) | both / 0.5.0 |
| E14 | Cost of consuming N deltas | `e2e_accum.R`, `accum_bench.R`, `httr2_many.R` | both |
| E15 | A UTF-8 character split across network chunks (agenticr's buffering) | inline Rscript | – |
| E16 | Re-run of the btw tool-schema size | `track10/tool_schema_size.R` | btw 1.5.0 |

---

## 3. ellmer (0.5.0 source; runtime 0.4.0 and 0.5.0)

Architecture (VERIFIED). `Chat` is an R6 object (`ellmer/R/chat.R:24`). Its private state holds `provider`,
`model`, `.turns`, `tools` and four `CallbackManager`s (`chat.R:735-746`). A call runs
`$chat()` → private generator `chat_impl()` (`chat.R:750-840`) → generator `submit_turns()`
(`chat.R:955-1112`) → `chat_perform()` (`ellmer/R/httr2.R:4-47`) → httr2. Provider behaviour is a set of
**non-exported** S7 generics (`ellmer/R/provider.R:66-423`), including `chat_request`, `chat_body`,
`chat_resp_stream`, `stream_parse`, `stream_content`, `stream_merge_chunks`, `value_turn` and `as_json`.
A `TurnAccumulator` R6 object builds partial turns while streaming (`chat.R:1375-1464`).

### 3.1 Send/receive

- **Request building** (VERIFIED). `method(chat_request, Provider)` = `base_request()` + `chat_path()` +
  `chat_body()` + `model@extra_args` + `extra_headers` (`provider.R:93-117`). Anthropic's
  `base_request` adds `anthropic-version`, the credentials header and retry-on-429/503/529
  (`ellmer/R/provider-claude.R:173-192`). The Anthropic body caches the system prompt and the last
  turn (`provider-claude.R:224`, `:791-795`) and defaults `max_tokens` to 4096 (`:311`). The OpenAI
  Responses body sets `store = FALSE` and, for reasoning models, `include = "reasoning.encrypted_content"`
  (`ellmer/R/provider-openai.R:201, 214`).
- **Four transport modes** (VERIFIED, `httr2.R:30-46`):
  - `value` → `req_perform()`;
  - `stream` → `req_perform_connection(req)`, which is **blocking** by default (`httr2.R:58`);
  - `async-value` → `req_perform_promise()`;
  - `async-stream` → `req_perform_connection(blocking = FALSE)` plus `later::later_fd()` on the curl fd set (`httr2.R:85-103`).
- **Which path runs.** `$chat()` streams only when `echo != "none"` (`chat.R:406`). Inside functions and
  scripts `echo` defaults to `"none"`, so programmatic `$chat()` does not stream at all. The mock logged
  `stream=FALSE` for such calls (E3 wire log, request #3). VERIFIED.
- **Streaming parse** (VERIFIED):
  - `chat_resp_stream()` → `httr2::resp_stream_sse()` (`provider.R:155-157`).
  - `stream_parse()` JSON-decodes each event and aborts with "Connection closed unexpectedly" on a `NULL` event (`provider-claude.R:320-331`).
  - `stream_merge_chunks()` accumulates text, thinking, signatures and tool JSON with the replacement function ``paste<-`` = `paste0` (`ellmer/R/utils.R:115-117`; `provider-claude.R:399-409`).
  - `stream_content_with_turns()` yields Content deltas only for `text_delta` and `thinking_delta`. Tool-argument deltas (`input_json_delta`) are merged silently (`provider-claude.R:339-381`). So a UI cannot show that the model is writing a 2 KB R snippet until the turn ends.
  - httr2's SSE parser costs about 0.19 ms per event, 5–17× a raw splitter (report 21 §1).
- **How deltas surface.**
  - E1: the sync generator delivered the first delta at **4.72 s** (httr2 1.3.0) and **2.12 s** (httr2 1.2.2); curl multi saw it at 0.24 s. The async generator was incremental.
  - E2: plain httr2 blocking reads delivered all 17 events at 4.60 s (1.3.0), or in two bursts at 1.95 s and 4.27 s (1.2.2); non-blocking reads were incremental in both.
  - Mechanism: httr2 1.3.0 `stream_pull()` asks `resp$body$read(stream_chunk_bytes)` with `stream_chunk_bytes = 65536` (printed `httr2:::stream_pull` and `httr2:::stream_chunk_bytes`); httr2 1.2.2 asks 1024 (`httr2:::resp_boundary_pushback`, printed). On a blocking curl connection the read returns only when the request is satisfied or the stream ends (report 09 §5.2).

  VERIFIED (mock). That real providers show the same is LIKELY.
- **Per-delta cost.**
  - E14: 250 / 500 / 1,000 / 2,000 deltas took 0.79–0.93 / 1.13–1.70 / 3.10–4.79 / **14.18–18.04 s** with 0.5.0, but 0.56 / 0.47 / 0.80 / **1.35 s** with 0.4.0 (saved logs). The verification re-run gave 1.38 / 3.13 / **11.76 s** (0.5.0) against 0.52 / 0.50 / **0.83 s** (0.4.0) for 500 / 1,000 / 2,000.
  - A raw `curl_fetch_memory()` of the same streams took 0.05–0.46 s, and httr2 SSE parsing alone 0.39–0.45 s at 2,000 events.
  - Mechanism: `TurnAccumulator$update_turn()` does `turn@contents <- c(turn@contents, list(content))` for every delta (`chat.R:1403-1409`), and `prop_list_of()`'s validator loops over the whole list on each assignment (`ellmer/R/utils-S7.R:119-131`). The micro-benchmark gave 8.51 s for 2,000 appends and 139 s for 5,000 (`$W/accum_bench_partial.out`).

  Timing VERIFIED. Attribution LIKELY.
- **Cancellation.**
  - `stream_controller()` is an R6 flag with a reason (`ellmer/R/stream-controller.R:65-115`). It is checked **between events** only (`httr2.R:61-64`; `chat.R:803-806`). The docs themselves say it stops "after the next chunk arrives" (`stream-controller.R:6-7`). In sync mode nothing can call it while the read blocks, and the granularity is the burst (E1). In async mode it works once the body is flowing: cancelled at 0.5 s, a `$stream_async()` ended at 0.65 s. But it cannot cancel during TTFT: `req_perform_connection(blocking = FALSE)` still blocks the R session until the headers arrive, so the cancel callback scheduled at 0.5 s ran at 3.35 s and the stream ended at 3.67 s (mock holding headers 3 s; Verification log V-8).
  - A user interrupt is not caught anywhere in the loop (E3). VERIFIED.
- **Timeouts.** `req_timeout(getOption("ellmer_timeout_s", 300))` (`httr2.R:120`) sets curl `timeout_ms`, a total-transfer limit (printed `httr2::req_timeout`). E4, with 1.5 s: "Operation timed out after 1502 milliseconds with 760 bytes received", on a stream that was actively delivering. So by default any single response that streams for more than 5 minutes is killed. VERIFIED.
- **Retries.**
  - `req_retry(max_tries = 3, retry_on_failure = TRUE)` (`httr2.R:122-128`). httr2's `req_perform_connection()` retries transient statuses before the body and sleeps `retry_after()`, which returns the header value unchanged with no cap (printed `httr2:::retry_after`, `httr2::req_perform_connection`). E8: two "Waiting 2s for retry backoff" lines, then success at 3.41 s.
  - A mid-stream Anthropic `overloaded_error` is not retried. The merge step calls `Sys.sleep(backoff_default(1))`, commented `# TODO: track number of retries` (`provider-claude.R:425-431`), and then keeps reading the closed stream. E5: "Connection closed unexpectedly" after 5.49 s.

  VERIFIED.
- **Rate limits.** `parallel_chat()` throttles with `req_throttle(capacity = rpm, fill_time_s = 60)` (`ellmer/R/parallel-chat.R:334`). The only provider-level handling is Mistral's: it reads `ratelimitbysize-reset` as the retry delay and throttles every request to 1 per second (`ellmer/R/provider-mistral.R:90-98`). The Anthropic, OpenAI and Google providers read no rate-limit headers. VERIFIED (grep of `R/`).

### 3.2 Conversation and message model

- **Types** (VERIFIED, `ellmer/R/turns.R:31-185`; `ellmer/R/content.R`).
  - Turns: `Turn`, `UserTurn`, `SystemTurn`; `AssistantTurn` with `json`, `tokens` (length 3), `cost`, `duration` and `finish_reason`; `AssistantPartialTurn` with `reason`.
  - Content: `ContentText`, `ContentThinking(thinking, extra)` (`content.R:470-477`), `ContentToolRequest(id, name, arguments, tool, extra)` (`:275-285`), `ContentToolResult(value, error, extra, request)` (`:329-353`), plus image, PDF, document, citation and web types.
  - Persistence: `contents_record()` / `contents_replay()` store S7 attributes with `version = 1` (`ellmer/R/content-replay.R`).
- **What it cannot represent, or represents wrongly:**
  - *Provenance.* `AssistantTurn` has no provider, model or API field (`turns.R:129-150`). Only the raw provider response is kept in `@json` (`provider-claude.R:546-552`), which usually includes the model name but is not normalised and is not consulted on replay. `ContentThinking@extra` means "signature" for Anthropic but "the whole reasoning item" for OpenAI (`provider-claude.R:519-522`; `provider-openai.R:351-353`). So the replay path has no way to know which provider owns the opaque data. VERIFIED.
  - *Redacted thinking.* `value_turn()` has no branch for `redacted_thinking` and falls through to `cli_abort("Unknown content type …", .internal = TRUE)` (`provider-claude.R:467-530`, abort at `:528`). E6: both versions abort; the value mode loses the turn. VERIFIED.
  - *Cross-provider replay.* E12, VERIFIED on both versions:
    - `as_json(ProviderOpenAI, ContentThinking)` returns `x@extra` (`provider-openai.R:504-510`), so the Anthropic turn becomes `[…,{"signature":"SIG-abc123=="},…]` in the Responses `input`.
    - `as_json(ProviderAnthropic, ContentThinking)` emits `signature = x@extra$signature` (`provider-claude.R:961-975`), so an OpenAI reasoning turn becomes `{"type":"thinking","thinking":"I reasoned.","signature":{}}`, and `encrypted_content` is dropped.
  - *Images in tool results.*
    - `tool_string()` makes every result a string (`content.R:384-390`); Anthropic sends `content = tool_string(x)` (`provider-claude.R:936-947`), and OpenAI sends `output = tool_string(x)` (`provider-openai.R:604-614`).
    - Content-valued results are "unrolled" into `"See <tool-content call-id=…> below."` plus extra user blocks (`chat-tools-content.R:1-73`). Its comment says "Very few providers support anything other than text results".
    - Anthropic `tool_result.content` accepts text, image, document and search_result blocks (report 07 line 262), and OpenAI `function_call_output.output` accepts an array with `input_image` (report 08 line 105). Anthropic also warns that text after tool results causes empty `end_turn` replies (report 07 lines 272-273), which is what the unrolling produces.

    VERIFIED (source); the empty-reply effect LIKELY.
  - *System-prompt sections.* `set_system_prompt()` collapses a character vector with `"\n\n"` into one `SystemTurn` (`chat.R:165-181`), and Anthropic receives one system block (`provider-claude.R:220-226`). There are no named, independently replaceable sections (Pi's model, decision register). VERIFIED.
  - *Tool-call ids.* For Responses, ellmer stores the output item's `id` (the `fc_…` item id) as the request id and replays it as `call_id` (`provider-openai.R:348-350, 591-601`). Pi keeps both ids, as `"{call_id}|{item_id}"` (report 03 §2.2). Whether this matters on the wire is UNCERTAIN.
  - *Stop reasons.* A `finish_reason` is standardised (`turns.R:128-172`). But every abnormal end of a stream (interrupt, HTTP error, parse error, overload) is recorded as `reason = "interrupted"`, because `finalize_turn()` uses `controller$reason %||% "interrupted"` (`chat.R:1425-1439`; E5, E6, E7, E10). VERIFIED.
  - *Steering.* No message kind exists, and none is needed without a queue (section 3.3).
- **What it does represent well** (VERIFIED):
  - Anthropic thinking with signature, and OpenAI reasoning with encrypted content, for **same-provider** replay (`store = FALSE` plus `include`);
  - Gemini `thoughtSignature` on tool requests (`provider-google.R:417, 711`);
  - citations, web search, and uploaded files.

### 3.3 The agent loop

- **Turn control.** `chat_impl()` loops `while (!is.null(user_turn))` with **no round limit** (`chat.R:781-839`). After each assistant turn, tool requests run and their results become the next user turn. VERIFIED.
- **Tool execution** (VERIFIED):
  - `invoke_tools()` is a coro generator over requests in source order, one at a time (`ellmer/R/chat-tools.R:31-78`). E11: two parallel tool calls ran at 1.84–2.35 s and 2.61–3.12 s (0.5.0), and at 0.34–0.86 s and 1.01–1.52 s (0.4.0), i.e. sequentially.
  - `$chat_async()` defaults to `tool_mode = "concurrent"` (`chat.R:513`), which runs *promise-returning* tools concurrently (`chat.R:914-940`). An ordinary R function still runs synchronously.
  - A tool that returns a promise in sync mode aborts with class `tool_async_error` (`chat-tools.R:64-72`).
- **Errors** (VERIFIED):
  - Good: `do.call(request@tool, args)` inside `tryCatch(error = …)` turns an R error into `ContentToolResult(error = e)` (`chat-tools.R:218-227`); an unknown tool gives the error result "Unknown tool" (`:206-208`); extra arguments give an error result (`:272-276`); with `echo = "none"` failures are summarised as an `ellmer_tool_failure` warning (`:353-381`).
  - Missing: (a) arguments are not validated against the schema (E9); (b) `maybe_on_tool_request()` catches only `ellmer_tool_reject`, so any other error in a callback aborts the loop (`chat-tools.R:282-295`); (c) interrupts are not handled (E3); (d) a `max_tokens` stop with a truncated tool call warns (`turns.R:358-380`) and then aborts on the JSON parse (E10). Pi instead fails such calls without running them (report 02 §1 item 5).
- **Human approval.** An `on_tool_request` callback may call `tool_reject(reason)`, which signals the class `ellmer_tool_reject` (`ellmer/R/tools-def.R:468-478`). Denial is the only structured outcome. The callback can prompt the user itself (ellmer's own example uses a blocking `utils::menu()` with an "Always / Once / No" allow-list, `tools-def.R:439-453`), but ellmer has no "ask" verdict that a UI layer handles. The callback's return value is ignored, so it cannot modify the arguments (`chat-tools.R:282-295`, `:58`), and there are no built-in permission modes. VERIFIED.
- **Abort.** Cancelling the controller breaks the loop *before* tools run (`chat.R:803-806`). Afterwards `complete_dangling_tool_requests()` answers every unanswered request with "Chat ended before the tool could be invoked." (`chat.R:1279-1300`). E3 showed this text sent after a tool that *had* run for 2.3 s. VERIFIED.
- **Steering and follow-ups.** There is no queue. A follow-up is simply another `$chat()`. The loop cannot be stepped from outside: track 10's single-step bridge produced duplicate tool results on 0.4.0 and 0.5.0 (track 10 §2.8.3, confirmed by its verifier). The 0.5.0 `on_request_start` hook is documented for compaction (`chat.R:699-715`). Using it to inject a steering message produced `assistant(tool_use) → user("STEER…") → user(tool_result)` on the wire (E11, request #13). Anthropic requires tool results to follow the `tool_use` turn immediately (report 07 §2.5). VERIFIED (wire); a real API rejecting it is LIKELY.

### 3.4 State and persistence

- The turns are a mutable list, `private$.turns`, appended and replaced in place (`chat.R:120-131`, `:1396-1439`). In streaming mode `begin_turn()` appends the user turn and an empty `AssistantPartialTurn` **before** the request returns (`chat.R:1396-1400`). That is why a 401 or an interrupt leaves an empty assistant turn behind (E3, E7). VERIFIED.
- There is no session file, no message ids, no tree and no fork (grep for "fork" over `ellmer/R/`: 0 files). The only on-disk state is the `batch_chat(path=)` JSON state file (`ellmer/R/batch-chat.R:85`). VERIFIED.
- `$clone()` is R6's shallow clone: the clone shares the `CallbackManager` objects, and only `clone(deep = TRUE)` separates them (E13). VERIFIED.

### 3.5 Concurrency

- `$chat()` and `$stream()` block the R session. Concurrency needs `$chat_async()` / `$stream_async()`, which require promises, coro and later. Track 15 measured the coro async-generator variant at 2–3× the CPU of a curl-multi reactor (report 15 §2.3). VERIFIED (there).
- `parallel_chat()` builds one non-streaming request per conversation (`stream = FALSE`, `parallel-chat.R:329`), runs `req_perform_parallel()` in lock-step rounds, and runs all tool calls sequentially in R between rounds (`parallel-chat.R:66-141`). It does not touch `pipewait`, so an HTTP/1.1 endpoint serialises the requests (report 15 §2.2). Every conversation starts from the same chat's provider, model, system prompt and history; only the new user prompt differs (`parallel-chat.R:73-94`), so it cannot mix models or system prompts. VERIFIED.
- Process-global state: `the$tokens` accumulates by provider/model (`ellmer/R/tokens.R:1-58`); E13 showed two chats merged into one row of 200/40 tokens. `token_usage()` is documented as a process-wide summary, and per-chat usage remains available from `$get_tokens()` (E13: 100/20). There is also `the$tool_context_stack` (`ellmer/R/tool-context.R:71, 113, 134`) and the memoised prices. Several agents can therefore share one session only through the async API, and their accounting and tool context are shared. VERIFIED; that the tool-context stack misbehaves under interleaved async tools is LIKELY, not tested.

### 3.6 Evaluation environment and copy safety

ellmer evaluates no model-written code. A tool is a user closure called with `do.call()` on arguments
decoded from JSON (`chat-tools.R:220`), and ellmer has no `envir` concept. Its `tool_context()` holds the
turn list, not user objects. Copy-safety issues arise in the packages that add an R-execution tool on top
(btw, section 5), not in ellmer itself. VERIFIED.

### 3.7 Extensibility

- **Tools.** `tool(fun, description, arguments = list(type_*()), annotations)` returns an S7 `ToolDef` that is itself callable (`tools-def.R:121-228`). Its annotations mirror MCP hints. VERIFIED (track 10, re-read).
- **Providers.** The `Provider` and `Model` classes are exported, but the generics that implement a provider are not, and their signatures changed between 0.4.0 and 0.5.0 (track 10 §5.8, verified there by `formals()`). A new provider *kind* (CLI, System 1) has no supported entry point. VERIFIED.
- **Hooks.** There are four callbacks: `on_tool_request`, `on_tool_result`, and (0.5.0) `on_request_start` and `on_request_end` (`chat.R:685-733`). None covers stream events, before-request transforms (other than `set_turns`), turn end or loop end. VERIFIED.
- **Churn.** ellmer keeps the deprecated `Turn(role =)` constructor because "this would cause chattr to fail tests" (`turns.R:52-55`). tidyprompt probes `exists("UserTurn")` to support both APIs (`tidyprompt/R/llm_providers.R:1008-1028`). Downstream code is coupled to ellmer's internals. VERIFIED.

### 3.8 What ellmer gets right (borrow; ellmer is MIT, © Posit — attribute any ported code)

1. Credentials as zero-argument functions, never stored, added with `req_headers_redacted()` (`ellmer/R/utils-auth.R:47-87`).
2. A partial turn that keeps whatever arrived, with a reason (`AssistantPartialTurn`) — with correct reasons (INFRA-04).
3. A cancellation token with a reason that can be reused across calls (`stream_controller()`).
4. Tool errors become results with an error flag sent back to the model, not exceptions (`chat-tools.R:218-227`).
5. Denial as a classed condition (`tool_reject()` → `ellmer_tool_reject`), which reads naturally in R.
6. `tool_annotations()` mirroring the MCP hints (read_only, destructive, idempotent, open_world).
7. The `type_*()` schema vocabulary, now a de-facto convention that mcplite re-implements (track 10 §2.7).
8. Same-provider replay of opaque reasoning: `store = FALSE` plus `include = "reasoning.encrypted_content"` for OpenAI; the signature kept for Anthropic.
9. Prompt-cache breakpoints on the system prompt and the last turn (`provider-claude.R:224, 791-795`).
10. A price table generated from litellm, cached under `tools::R_user_dir()` and gated by `schema_version` (`ellmer/R/prices.R`).
11. Structured output: native `json_schema` where the model supports it, otherwise a forced tool (`provider-claude.R:233-252`).
12. Resumable batch jobs, with a state file keyed by a hash of provider, model and prompts (`batch-chat.R`).
13. Optional OpenTelemetry spans (`ellmer/R/otel.R`).
14. `df_schema()`: a one-line-per-column data frame summary (track 10 §2.5).

### 3.9 Why ellmer's infrastructure is unsuitable for gptr (evidence)

| # | Reason | Evidence |
|---|---|---|
| U1 | The streaming transport the console uses is not incremental on current httr2, and costs O(n²) per turn on current ellmer | E1, E2, E14 |
| U2 | An interrupt cannot be turned into steer or continue; partial output is lost or replayed as "[empty string]"; tool interruption is misreported | E3; `chat.R:1279-1300` |
| U3 | A total transfer timeout kills long generations | E4; `httr2.R:120` |
| U4 | Mid-stream overloads are not retried; Retry-After is uncapped | E5, E8; `provider-claude.R:425-431` |
| U5 | Valid provider output (`redacted_thinking`) aborts the run | E6 |
| U6 | No provenance field (only the raw `@json`), so hand-off corrupts reasoning items | E12; `turns.R:129-150` |
| U7 | No argument validation; a truncated tool call aborts | E9, E10 |
| U8 | The loop is unbounded, not steppable, and has no steering queue; hooks cannot steer | E11; track 10 §2.8.3 |
| U9 | Mutable in-memory history; empty partial turns on error; no ids, tree, fork or append-only log | E7, E13; `chat.R:1396-1400` |
| U10 | Process-global usage and tool context; `parallel_chat()` is lock-step and non-streaming | E13; `parallel-chat.R:329` |
| U11 | Providers can only be extended through unexported generics whose signatures change; no CLI or System 1 kind | track 10 §2.4, §5.8 |
| U12 | Tool results are text-only; images are unrolled into user content | `chat-tools-content.R:1-73` |

---

## 4. Raw experiment outputs (abridged; full logs in `$W/run_*.out`, `$W/log_*/requests.jsonl`)

**E1 — arrival of deltas.** 12 text deltas (18 SSE events) at 0.25 s intervals, chunked body; warm-up call first.
The identity-body runs gave the same pattern.

```text
ELLMER 0.5.0 HTTR2 1.3.0 CURL 7.0.0 chunked = 1
ellmer $stream(): n = 13  arrival s = 4.72 5.50 5.50 5.51 5.51 5.51 5.51 5.52 5.52 5.52 5.53 5.53 5.58
ellmer $stream_async(): n = 13  arrival s = 2.27 2.27 2.28 2.29 2.38 2.63 2.89 3.15 3.40 3.65 3.91 4.18 4.95
curl multi: SSE events = 18  arrival s = 0.24 0.51 0.76 1.01 1.27 1.52 1.77 2.03 2.29 2.54 2.79 3.05 3.31 3.56 3.82 4.08 4.33 4.58
ELLMER 0.4.0 HTTR2 1.2.2 CURL 7.0.0 chunked = 1
ellmer $stream(): n = 13  arrival s = 1.91 2.12 2.12 2.12 2.12 4.19 4.19 4.19 4.19 4.19 4.19 4.19 4.45
ellmer $stream_async(): n = 13  arrival s = 0.62 0.85 1.10 1.36 1.62 1.88 2.14 2.39 2.65 2.91 3.17 3.43 4.21
curl multi: SSE events = 18  arrival s = 0.25 0.51 0.76 1.02 1.28 1.53 1.79 2.06 2.31 2.57 2.83 3.08 3.33 3.59 3.85 4.11 4.36 4.62
```

On 0.5.0 the first async delta came at 2.27 s. This looks like a one-time start-up cost of the async path,
since the spacing afterwards is the true 0.25 s (UNCERTAIN cause).

**E2 — httr2 alone** (`resp_stream_sse()`, 17 events):

```text
HTTR2 1.3.0 CURL 7.0.0
blocking=TRUE: events=17 arrival s = 4.60 4.60 4.60 4.60 4.60 4.60 4.60 4.60 4.60 4.60 4.60 4.60 4.60 4.61 4.61 4.61 4.61
blocking=FALSE: events=17 arrival s = 0.03 0.29 0.54 0.80 1.06 1.32 1.57 1.83 2.09 2.35 2.61 2.87 3.12 3.38 3.64 3.90 4.15
HTTR2 1.2.2 CURL 7.0.0
blocking=TRUE: events=17 arrival s = 1.95 1.95 1.95 1.95 1.95 1.95 1.95 4.27 4.28 4.28 4.28 4.28 4.28 4.28 4.28 4.28 4.53
blocking=FALSE: events=17 arrival s = 0.02 0.28 0.53 0.79 1.05 1.31 1.57 1.83 2.09 2.34 2.60 2.86 3.12 3.38 3.64 3.90 4.16
```

**E3 — interrupts** (`driver_ellmer.R` sends `p$interrupt()`; times are measured from the child's start).

```text
===== e050 | case=slow_int                      (SIGINT 1.21 s after READY, mid-body)
  | OUTCOME INTERRUPT condition reached top level 2.47s
  |   [1] ellmer::UserTurn contents={ellmer::ContentText} text="hi"
  |   [2] ellmer::AssistantPartialTurn contents={} text="" reason=interrupted tokens=NA/NA/NA
  | SECOND completed
server.log: slow client went away: ignoring SIGPIPE signal
wire of the SECOND request (log_e050/requests.jsonl #2):
    user : [{"type":"text","text":"hi"}]
    assistant : [{"type":"text","text":"[empty string]"}]
    user : [{"type":"text","text":"second question",...}]
===== e050 | case=ttft_int                      (SIGINT 1.00 s after READY; server holds headers for 3 s)
  | OUTCOME INTERRUPT condition reached top level 2.40s
  |   [2] ellmer::AssistantPartialTurn contents={} text="" reason=interrupted
===== e050c | case=tool_int                     (SIGINT 3.50 s after READY; 4 s tool started at 1.24 s)
  | TOOL start 1.24s
  | OUTCOME INTERRUPT condition reached top level 3.55s
  |   [2] ellmer::AssistantTurn contents={ellmer::ContentText,ellmer::ContentToolRequest} ...
wire of the next request (log_e050c/requests.jsonl #2):
    user : [{"type":"tool_result","tool_use_id":"toolu_01","content":"Tool calling failed with error Chat ended
            before the tool could be invoked.","is_error":true},{"type":"text","text":"continue please",...}]
===== e040 | case=slow_int                      (ellmer 0.4.0, SIGINT 1.21 s)
  | OUTCOME INTERRUPT condition reached top level 1.37s
  | TURNS n = 0
```

**E4 — total timeout** (`options(ellmer_timeout_s = 1.5)`, 4-s stream):

```text
e050 | OUTCOME ERROR <curl_error_operation_timedout/...> Timeout was reached [127.0.0.1]: Operation timed out after
       1502 milliseconds with 760 bytes received 2.99s ; [2] AssistantPartialTurn contents={} reason=interrupted
e040 | ... Operation timed out after 1500 milliseconds with 881 bytes received 1.81s ; TURNS n = 0
```

**E5 — mid-stream `overloaded_error`:**

```text
e050 | partial answerOUTCOME ERROR <rlang_error/...> Connection closed unexpectedly 5.49s
     |   [2] ellmer::AssistantPartialTurn contents={ellmer::ContentText} text="partial answer " reason=interrupted
e040 | partial answerOUTCOME ERROR <simpleError/error/condition> argument is of length zero 4.33s ; TURNS n = 0
```

**E6 — `redacted_thinking`:**

```text
e050 stream | OUTCOME ERROR <rlang_error> Unknown content type "redacted_thinking". | i This is an internal error that
            | was detected in the ellmer package. ...  [2] AssistantPartialTurn text="visible answer" reason=interrupted
e050 value  | OUTCOME ERROR <rlang_error> Unknown content type "redacted_thinking". ...  TURNS n = 0
e040 stream | OUTCOME ERROR <rlang_error> Unknown content type "redacted_thinking". ...  TURNS n = 0
```

**E7 — HTTP 401:**

```text
e050 stream | OUTCOME ERROR <httr2_http_401/...> HTTP 401 Unauthorized. | i invalid x-api-key [authentication_error]
            |   [1] UserTurn "hi"  [2] AssistantPartialTurn contents={} text="" reason=interrupted
e050 value  | same error; TURNS n = 0
e040 stream | same error; TURNS n = 0
```

**E8 — 429 with `retry-after: 2`:** "Waiting 2s for retry backoff" twice, then `after-retry`, completed at 3.41 s.

**E9 — tool-argument validation** (`tool(f, arguments = list(code = type_string(), n = type_integer()))`,
invoked through `ellmer:::invoke_tool()`; identical on 0.4.0 and 0.5.0):

```text
{"code":"1+1","n":3}                     -> value=code=1+1 (character) n=3 (integer) | error=NULL
{"n":3}                                  -> value=code=NA (character) n=3 (integer) | error=NULL
{"code":"1+1","n":"three"}               -> value=code=1+1 (character) n=three (character) | error=NULL
{"code":[1,2],"n":3}                     -> value=code=1 (list) n=3 (integer) code=2 (list) n=3 (integer) | error=NULL
{"code":"1+1","n":3,"extra":true}        -> value=NULL | error=Unused argument: extra
```

A missing required argument becomes `NA` through `convert_from_type()` (`ellmer/R/chat-structured.R:86-95`).

**E10 — `max_tokens` inside a tool call:**

```text
e050 | WARNING: Response was truncated because it hit the `max_tokens` limit.
     | OUTCOME ERROR <simpleError> parse error: premature EOF | {"label": "unfinished | (right here) ------^
     |   [2] AssistantPartialTurn text="writing code " reason=interrupted
e040 | OUTCOME ERROR <simpleError> parse error: premature EOF ... TURNS n = 0
```

**E11 — parallel tool calls and the steering hack:**

```text
par (0.5.0) | RESULT toolu_A A 1.84s 2.35s | RESULT toolu_B B 2.61s 3.12s      (sequential)
par (0.4.0) | RESULT toolu_A A 0.34s 0.86s | RESULT toolu_B B 1.01s 1.52s
steer_hack wire (log_e050b/requests.jsonl #13):
    user : [{"type":"text","text":"hi"}]
    assistant : [{"type":"text","text":"calling tool "},{"type":"tool_use","id":"toolu_01","name":"slow_tool",...}]
    user : [{"type":"text","text":"STEER: use TPM instead"}]
    user : [{"type":"tool_result","tool_use_id":"toolu_01","content":"slept","is_error":false,...}]
```

**E12 — cross-provider replay** (serialised with the non-exported `ellmer:::chat_body()`, for measurement only):

```text
OpenAI /responses input built from the Anthropic turns:
 [{"role":"user","content":[{"type":"input_text","text":"hi"}]},{"signature":"SIG-abc123=="},
  {"role":"assistant","content":[{"type":"output_text","text":"The answer is 42."}]}]
Anthropic messages built from an OpenAI turn:
 [{"role":"user","content":[{"type":"text","text":"q"}]},{"role":"assistant","content":[{"type":"thinking",
  "thinking":"I reasoned.","signature":{}},{"type":"text","text":"Answer from GPT."}]},{"role":"user",...}]
```

Output is identical on 0.4.0 and 0.5.0.

**E13 — global accounting and clones:**

```text
tokens_global | a$get_tokens(): input 100 output 20 | token_usage(): Anthropic claude-mock-1 input 200 output 40
clone (0.5.0) | shallow clone shares the on_tool_request CallbackManager: TRUE | deep clone shares it: FALSE
```

**E14 — consuming N deltas** (two runs of 0.5.0, one of 0.4.0 shown; the mock sends with no delay):

```text
ELLMER 0.5.0 HTTR2 1.3.0
n=  250 deltas: ellmer $stream() consumed 251 chunks in   0.79s | raw curl fetch of same stream  0.05s (30376 bytes)
n=  500 deltas: ellmer $stream() consumed 501 chunks in   1.13s | raw curl fetch of same stream  0.08s (60126 bytes)
n= 1000 deltas: ellmer $stream() consumed 1001 chunks in   3.10s | raw curl fetch of same stream  0.15s (119626 bytes)
n= 2000 deltas: ellmer $stream() consumed 2001 chunks in  14.18s | raw curl fetch of same stream  0.43s (238626 bytes)
(rerun: 0.93 / 1.70 / 4.79 / 18.04 s)
ELLMER 0.4.0 HTTR2 1.2.2
n=  250 ... 0.56s | n=  500 ... 0.47s | n= 1000 ... 0.80s | n= 2000 deltas: ... 1.35s
httr2 1.3.0 resp_stream_sse + parse_json alone: 1005 events 0.25s, 2005 events 0.39s (httr2 1.2.2: 0.22s, 0.45s)
micro-benchmark of turn@contents <- c(turn@contents, list(ContentText())):  2000 appends 8.51s; 5000 appends 139.19s
```

**E15 — a UTF-8 character split across chunks** (`LANG=en_US.UTF-8`): `strsplit()` on the first half gives
`NA` with the warning "input string 1 is invalid", and `trimws()` errors "input string 1 is invalid UTF-8".
Pasted together, the two halves are valid UTF-8 and parse to `中文`. Verification re-run (V-12): feeding
agenticr's own write-callback body (`agenticr/R/llm.R:160-173`) a stream split inside `中` gives, in
`en_US.UTF-8`, the `strsplit()` warnings and then the error "invalid multibyte string, element 1" from
`nchar(raw_text)`. The callback throws, so the whole streamed response aborts; even the complete event
earlier in the same chunk is not delivered.

**E16 — btw's tool-schema size** (re-run of track 10's script): 31 tools = 46,235 characters (~11.6k tokens),
`btw_tool_run_r` alone = 2,679. VERIFIED, and matches track 10.

---

## 5. btw 1.5.0 and mcptools 1.0.3 (Posit; both built on ellmer)

**(1) Send/receive.** btw has no transport of its own. `btw_client()` returns an ellmer `Chat` with btw's
system prompt, tools and skills (`btw/R/btw_client.R:129-189`). It runs in the console through ellmer's
`live_console()` or in Shiny through `btw_app()`. Every finding in section 3 applies. VERIFIED.

**(2) Message model.** ellmer's. Sub-agent answers are wrapped as text `<subagent-response session_id=…>`
(`btw/R/tool-agent-subagent.R:168-190`). VERIFIED.

**(3) Loop.** ellmer's.
- The `btw_tool_agent_subagent` tool calls `chat$chat(prompt)` synchronously inside the parent's tool call (`tool-agent-subagent.R:480`). A sub-agent therefore blocks the parent. Because ellmer runs tools sequentially, two sub-agents the model requested in one turn run one after the other. VERIFIED (source plus E11).
- There are no permission modes. `btw_tool_run_r` is opt-in only: option `btw.run_r.enabled`, the environment variable `BTW_RUN_R_ENABLED`, or the "run" group (`btw/R/tool-run.R:31-48, 324-329`). VERIFIED.

**(4) State.** Sub-agent sessions live in a package-level environment, `.btw_subagent_sessions`
(`tool-agent-subagent.R:804-852`). A `session_id` lets the model resume a sub-agent within the same R
process; nothing survives a restart. `btw_app()` stores chat history with RSQLite (track 10,
verification #53). VERIFIED.

**(5) Concurrency.** None beyond ellmer. Sub-agents are nested and synchronous. VERIFIED.

**(6) Evaluation.**
- `btw_tool_run_r_impl(code, .envir = global_env())` calls `evaluate::evaluate(…, envir = .envir, stop_on_error = 1, new_device = TRUE)` (`tool-run.R:123, 232-238`). evaluate leaves sticky references that force copies (report 12 §A2).
- The wd, options and env vars are restored with `withr::local_*()` (`tool-run.R:166-168`), but new options and new env vars are not restored (report 12 §A3).
- There is no timeout: a grep for `setTimeLimit` and `timeout` in `tool-run.R` finds nothing.

VERIFIED.

**(7) Extensibility.**
- btw exposes 30 default tools plus opt-in `run_r` (E16), and supports skills, `btw.md`, agents in `.claude/agents` and skills in `.agents/skills` (track 10 item 13).
- mcptools serves any list of ellmer tools as an MCP server (`mcptools/R/server.R`). `mcp_session()` exposes the live session over a nanonext "poly" socket. Incoming calls are serviced through `promises` only when R is idle (`mcptools/R/session.R:1-38, 42-69, 350-355`). Payloads are R-serialised and HMAC-sealed (`mcptools/R/socket-auth.R`). On Windows, named pipes are documented as "not a security boundary" (track 10 §2.6).

VERIFIED.

**(8) Borrow.**
- btw: short tool descriptions and the "runs in a global environment" warning text as a template for gptr's `r` tool (report 12 §A3); the working-directory restriction `check_path_within_current_wd()` (`btw/R/tool-files-read.R:338`); hash-anchored edits; opt-in dangerous tools; resumable sub-agent session ids; skill discovery.
- mcptools: servicing the live session when idle through `later`, and MAC-sealed local IPC — both the pattern for gptr-as-MCP-server (D-14; report 16 §2.11).

**(9) Unsuitable.**
- btw inherits every ellmer transport and loop limitation (U1–U12).
- It hard-codes the global environment and has no timeout.
- Sub-agents are synchronous and registered in memory.
- The dependency closure is 70 packages, with a Rust toolchain needed from source (track 10 §2.2).
- The full default tool list costs ~11.6k tokens of schema per request (E16).

VERIFIED.

---

## 6. tidyllm 0.6.0

**(1) Send/receive** (VERIFIED unless marked):
- `perform_chat_request()` streams with `httr2::req_perform_connection(.request, blocking = TRUE)` (`tidyllm/R/perform_api_requests.R:65`). On httr2 1.3.0 that path is buffered (E2). That the same applies to tidyllm is LIKELY, since it makes the same call.
- 0.6.0 introduced one shared stream pump per provider (`tidyllm/R/stream_pump.R:1-240`). It separates transport (`read_stream_chunk()`), parsing (`parse_stream_event()` returning `stream_event(kind = text|thinking|error|done, …)`) and the sink.
- It has an **idle** deadline between events rather than a total one (`stream_pump.R:101-104, 164-180`). But the pump checks the deadline only when a read returns nothing, which a blocking read does only at the end of the stream (the file's own comment, `:118-120`). So on the console path the idle deadline cannot fire. LIKELY.
- Non-stream requests retry on 429/503 (`perform_api_requests.R:14-30`).
- Rate-limit headers are parsed into a package-global environment `.tidyllm_rate_limit_env` (`tidyllm/R/rate_limits.R:10-49`).

**(2) Message model.**
- `LLMMessage` is an S7 *value* with `message_history` = a list of `{role, content, json, media, files, meta, logprobs}` (`tidyllm/R/LLMMessage.R:19-23, 48-77`).
- Claude thinking and its signature are kept only in `meta$specific_metadata`, and only for the first thinking block (`tidyllm/R/api_claude.R:173-197`). The replayed Claude history contains images, PDFs as text, files and text only (`api_claude.R:75-122`).
- It cannot represent tool calls or tool results in the history (next item). VERIFIED.

**(3) Loop.**
- `process_tool_loop()` runs at most `.max_tool_rounds = 10` and then calls `stop()` (`tidyllm/R/tools.R:341-366`).
- Tool calls and results live only in the request body (`append_tool_messages`). After the loop, only the final assistant text is added to the `LLMMessage` (`tidyllm/R/chat_pipeline.R:141-188`). The agent's actions are therefore lost from the history.
- `run_tool_calls()` for the chat-completions dialect (`tidyllm/R/api_chat_completions.R:171-221`):
  - parses arguments with `simplifyVector = TRUE`;
  - turns an unparseable call or an unknown tool into `warning()` + `NULL`, then drops it with `purrr::compact()`, leaving a call id with no result;
  - calls `do.call(tool_function, …)` with no `tryCatch`, so an R error in a tool aborts the chat. The Claude, Gemini and OpenAI Responses methods do the same (`api_claude.R:255-257`, `api_gemini.R:296-300`, `api_openai.R:235`); only the Ollama method catches errors (`api_ollama.R:181-190`).
- There is no approval or steering. Abort exists only for async `send_chat()` jobs: `cancel_job()` closes a streaming job's connection (`tidyllm/R/async_chat.R:434-449`). The synchronous path has none.

VERIFIED.

**(4) State.** No persistence and no ids. An `LLMMessage` value can be saved, but it lacks the tool rounds. VERIFIED.

**(5) Concurrency.** `send_chat()` returns a job driven by `later` (`tidyllm/R/async_chat.R:1-20`), with
`check_job()`, `fetch_job()`, `get_partial()` and `cancel_job()`. But "The tool loop is blocking, and
knowingly so in this release" (`async_chat.R:223-227`). There are also batch APIs for several providers.
VERIFIED.

**(6) Evaluation.** tidyllm has no R-execution tool. N/A.

**(7) Extensibility.** Providers are S7 classes (`api_claude <- new_class("Claude", APIProvider)`,
`api_claude.R:4`) with methods on generics such as `to_api_format` and `parse_stream_event`. VERIFIED.

**(8) Borrow:** the single stream pump with typed event kinds; idle-not-total deadlines; "a stream that ends
without its terminal event is an error" (`stream_pump.R:165-171`); rate-limit header parsing; the job-handle
vocabulary (`check / fetch / cancel / get_partial`); and `.dry_run` returning the built request for tests
(`chat_pipeline.R:191-194`).

**(9) Unsuitable:**
- the history drops tool rounds;
- tool errors throw, and orphaned calls are possible;
- the tool loop blocks;
- the synchronous transport is blocking;
- it has no interrupt handling, steering or session tree (only `cancel_job()` for async jobs);
- the pipe creates a new *value* at each step, the opposite of S-8's single session object that `|>` must extend.

VERIFIED.

---

## 7. corteza 0.7.1 and llm.api 0.1.9

corteza's loop is `llm.api::agent()` (`corteza/R/turn.R:717`), so the two are reviewed together.

**(1) Send/receive** (VERIFIED):
- llm.api's agent requests are **non-streaming** `curl::curl_fetch_memory()` (`llm.api/R/agent.R:695-702`). The Codex route streams with `curl_fetch_stream()` (`llm.api/R/openai-codex.R:286`), and `chat()` has a writefunction path (`llm.api/R/chat.R:591-592`).
- There is no retry anywhere in llm.api (a case-insensitive grep for `retry` over `llm.api/R/` finds 0 matches) and no rate-limit handling.
- Claude subscription OAuth sends `Authorization: Bearer` plus `anthropic-beta: oauth-2025-04-20` (`llm.api/R/anthropic-claude.R:26-71`). This conflicts with Anthropic's terms (track 10 item 12).

**(2) Message model** (VERIFIED):
- The history is kept in each **provider's native format** (`agent.R:486` `assistant_message = list(role = "assistant", content = resp$content)`). Replay to the same provider therefore round-trips everything, signatures included (LIKELY), but hand-off needs conversion and none exists.
- Tool results never carry `is_error` (grep `is_error` over `llm.api/R`: 0 matches). Errors become the string `"Error: …"` (`agent.R:335-343, 640-670`).

**(3) Loop** (VERIFIED):
- `max_turns = 20` (`agent.R:81-87, 201, 365`); tools run sequentially; a handler error becomes that string.
- A `history_callback` fires after every appended message (`agent.R:258-262, 689`). corteza uses it to persist, and to repair a history cut by Ctrl-C or a denial: it synthesises `"[Interrupted before completion]"` results for the unfinished calls of the current turn and appends a marker (`corteza/R/interrupt.R:1-75`).
- corteza has permission and plan modes (track 10 §2.3).

**(4) State.** corteza appends JSONL transcripts (`corteza/R/session.R:457, 642`): a `"version":2` header and
flat Pi-shaped messages with no `id`/`parentId` tree (track 10, verification #39). The `sessions.json`
metadata is rewritten whole (`session.R:170`). VERIFIED.

**(5) Concurrency.** corteza sub-agents are `callr::r_session` children (`corteza/R/subagent.R:3, 542`).
Nothing concurrent runs in-process. VERIFIED (track 10, re-read).

**(6) Evaluation.** Code runs in `globalenv()`. Hidden `.h_NNN` handles for large results are copied *into*
the global environment, and the package accepts the R CMD check NOTE for this (`corteza/R/handles.R:135-160`;
`corteza/R/tool-impl.R:433-476`). VERIFIED.

**(7) Extensibility.** Tools are R functions with schemas derived from formals and roxygen
(`corteza/R/schema.R:196-330`). It has skills, an MCP server (`serve()`) and llm.api's MCP client. VERIFIED (partly via track 10).

**(8) Borrow:**
- corteza's interrupted-tool repair and its honest marker;
- llm.api's per-message history callback — the hook gptr's append-only store needs;
- the cache-write split into 5 min and 1 h TTLs in cost (`llm.api/R/agent.R:229-248`; `llm.api/R/cost.R:26-66`), priced at 1.25× and 2× input;
- corteza's handles for large results and its provenance of new bindings;
- corteza's explicit resolution of `bash` on Windows (report 10 §6).

**(9) Unsuitable:**
- native-format history, so no hand-off;
- a non-streaming agent loop;
- no `is_error`;
- global-environment evaluation that writes handles;
- a subscription route that breaks provider terms;
- a flat transcript.

VERIFIED.

---

## 8. aisdk 1.4.12 (YuLab-SMU; 42k lines, 215 exports)

**(1) Send/receive** (VERIFIED):
- Streaming uses a blocking `httr2::req_perform_connection(req)` (`aisdk/R/utils_http.R:424-426`), the same path as E2.
- Timeouts are layered: total (off by default), first byte (300 s), connect (10 s) and idle (120 s) (`utils_http.R:226-318`). They are libcurl options (`connecttimeout`, `server_response_timeout`, `low_speed_limit = 1` + `low_speed_time`), so they are enforced inside libcurl and keep working under blocking reads.
- Its own retry loop honours `retry-after-ms` and `retry-after` and multiplies by a backoff factor, with no cap (`utils_http.R:612-633`).
- The Anthropic stream is retried as a whole on start or transport errors (`aisdk/R/provider_anthropic.R:563-590`). Deltas already delivered are not tracked, so a restart after partial output may duplicate text. UNCERTAIN (not run).

**(2) Message model.** aisdk streams Anthropic thinking as reasoning text: `map_anthropic_chunk()` routes
`thinking` block starts and `thinking_delta` to the aggregator (`aisdk/R/sse_aggregator.R:515-539`). But it
never captures `signature_delta` or `redacted_thinking`: a grep for `signature_delta`/`redacted_thinking`
over the whole package matches nothing, and no thinking signature is stored anywhere. So thinking
cannot be replayed with its signature. Tool-argument deltas (`input_json_delta`) are accumulated silently
and not surfaced (`sse_aggregator.R:150-154`). VERIFIED (source and grep). That thinking is lost inside tool
loops is UNCERTAIN.

**(3) Loop.** `generate_text(max_steps = 1)` (`aisdk/R/core_api.R:566`). `HookHandler` offers
`on_generation_start/end`, `on_tool_start/end` and `on_tool_approval` (returns TRUE/FALSE)
(`aisdk/R/hooks.R:12-60`). The console catches an interrupt at the prompt only (`aisdk/R/console.R:318-330`).
There is no steering. VERIFIED.

**(4) State** (VERIFIED):
- `ChatSession$save()` writes a whole-session snapshot to `.rds` or `.json` (`aisdk/R/session.R:551-566`).
- The console also keeps an **append-only JSONL event log with named branches** (`aisdk/R/session_event_store.R:41-58, 108-160`). It is written under `getwd()/.aisdk/sessions`, and `dir.create()` is called without asking (`:23-38`).
- Event and branch ids are built with `stats::runif(1)` (`:50, 141`), which changes the user's `.Random.seed`. Report 02 §1 item 18 requires that ids must not.
- The root can be overridden through the session metadata `console_session_store_root` (`:23-31`); `getwd()/.aisdk/sessions` is the default.

**(5) Concurrency.** Code execution and some tools run in `callr` background processes
(`aisdk/R/r_introspect_tools.R:13, 204-215`). No multi-agent reactor was found. LIKELY (not all 42k lines read).

**(6) Evaluation.** aisdk has both kinds.
- The `r_eval` introspection tool runs R code "in an isolated subprocess" (`r_introspect_tools.R:13`).
- In-process evaluation also exists. `SharedSession$execute_code()` runs `eval(parse(text = code), envir = env)` in a scope environment whose root is the `ChatSession` environment (`shared_session.R:176-207, 521-533`). `SandboxManager$execute()` evaluates model code in a child of `parent_env`, default `new.env(parent = baseenv())`, after an AST safety check (`sandbox.R:59-60, 158-170`; exported `create_r_code_tool()`).
- The `ChatSession` environment is `new.env(parent = globalenv())` unless the user supplies `envir`, and aisdk writes hidden bindings such as `.capability_models` and `.skill_registry` into it (`session.R:114-124`).

So computation can be in-memory, but not in the caller's environment by default. New bindings land in aisdk's
session or sandbox environments, and a user-supplied environment receives aisdk's own bookkeeping objects.
REQ-22 is met only partially. VERIFIED (source; not run).

**(7) Extensibility.** Providers, skills, MCP, a sandbox, hooks and agent libraries. The breadth is large. VERIFIED (exports).

**(8) Borrow:** layered timeouts enforced in libcurl; `retry-after-ms`; a branch-aware append-only event log; the list of hooks, including approval.

**(9) Unsuitable:**
- blocking transport;
- no reasoning-signature model;
- evaluation in aisdk-owned session or sandbox environments (or a subprocess), not the caller's, with bookkeeping bindings written into the session environment;
- ids that consume the RNG stream;
- writes into the project directory without consent (CRAN policy, report 13);
- no steerable loop.

VERIFIED.

---

## 9. agenticr 0.3.3

**(1) Send/receive** (VERIFIED):
- It uses `httr::POST(…, httr::write_stream(function(x) …))`, speaks the OpenAI chat-completions dialect only (plus "local"), and does not retry (`agenticr/R/llm.R:114-200`).
- Each network chunk is turned into a string with `rawToChar()` and appended to a *string* buffer, which is then split with `strsplit()` (`llm.R:159-168`). E15 shows that a chunk ending inside a UTF-8 character makes `strsplit()` return `NA`. Running agenticr's callback body on such a split (V-12) goes further: `nchar(raw_text)` then errors with "invalid multibyte string, element 1", so the write callback throws and the streamed response aborts. LIKELY for agenticr end to end (the callback logic was run in isolation in a UTF-8 locale; agenticr itself was not run).

**(2) Message model.** OpenAI chat messages plus a `reasoning_content` text. There are no signatures. VERIFIED.

**(3) Loop.**
- A REPL loop with a per-turn token budget (`agenticr/R/repl.R:673-690`).
- Hard truncation drops leading `tool` messages and trims the history (`llm.R:304-318, 376-381`).
- An `options(error =)` interceptor routes natural language typed at the R prompt to the agent (`repl.R:1278-1330`).

VERIFIED.

**(4) State.** Per-session history in the package environment. VERIFIED (track 10).

**(5) Concurrency.** None. VERIFIED.

**(6) Evaluation.** `eval(expr, envir = .GlobalEnv)` inside `withVisible()` (`agenticr/R/tools.R:563-565`); `withVisible()` holds the value in a list, which is a sticky-reference pattern (report 12 §1 item 2). VERIFIED (source); the copy effect LIKELY.

**(8) Borrow:** the error-interceptor UX idea (report 18); the per-turn token budget.

**(9) Unsuitable:** httr (superseded), one dialect, byte-unsafe stream decoding, global environment. VERIFIED.

---

## 10. chattr, gptstudio, mall, rollama, openai — compact review

| Package | (1) Send/receive | (2) Model | (3) Loop | (4)/(5) State and concurrency | (6) Evaluation | (8) Borrow | (9) Unsuitable because |
|---|---|---|---|---|---|---|---|
| **chattr 0.3.1** (mlverse) | ellmer `$stream()` / `$stream_async()` (`chattr/R/backend-ellmer.R:19-35`) | Plain `{role, content}` text; converts it back with the deprecated `ellmer::Turn(role =)` (`:76-93`) | ellmer's | One global `Chat` in `ch_env` (`chattr/R/chattr-package.R:21`; `backend-ellmer.R:40-63`) | Reads **every** global object, `ls(.GlobalEnv)` then `mget()` on each, to find data frames (`chattr/R/ch-context.R:59-62`), which forces promises (report 12 §C1) | The explicit warning that files and data frames are sent externally (`chattr/R/backend-openai.R:21-44`) | A single global chat; inherits ellmer; unsafe context gathering. VERIFIED |
| **gptstudio 0.4.0** (2024) | Streaming only with a Shiny session: "Stream requires a shiny session object" (`gptstudio/R/api_perform_request.R:56-57`); `curl_fetch_stream()` "blocks the R console until the stream finishes" (`gptstudio/R/service-openai_streaming.R:43-50, 61-63`) | Chat text | No tool calling at all (0 matches for `tool_calls`, `tool_use` or `function_call`) | Shiny module state | – | Using `sendCustomMessage()` to stream into a UI | Stale on CRAN since 2024; no tools; UI-bound transport. VERIFIED |
| **mall 0.2.0** (mlverse) | ellmer `parallel_chat_text()` (`mall/R/m-backend-submit.R:96-133`) | Free text matched against labels | – | Global backend `.env_llm` (`mall/R/mall.R:11`); cache keyed by `rlang::hash(c(ellmer_obj, prompt, x))` (`m-backend-submit.R:107`) | – | Vectorised verbs over data frames; response cache; `preview =` | Invalid answers become `NA` with a warning (`mall/R/m-vec-prompt.R:33-55`), which breaks `if()` (decision register); no probabilities; `llm_vec_verify()` returns a factor (`mall/R/llm-verify.R:67-82`). VERIFIED |
| **rollama 0.3.1** | Blocking `req_perform_connection()` + `resp_stream_lines()` per NDJSON line (`rollama/R/progress.R:1-31`) | Ollama messages; `think`, `logprobs` | Tools are *not executed*: the documentation tells the user to run them by hand (`rollama/R/chat.r:181-215`) | Global `the$prompts` / `the$responses`, ordered by `Sys.time()` names (`chat.r:429-469, 482-491`); the prompt is stored before the request, so a failure leaves an orphan | – | Logprobs for emulated System 1 (with LLMR, rtemis.llm; track 10 §2.7) | No loop; global history; blocking. VERIFIED |
| **openai 0.4.1** (2023) | `httr::POST`; `stream` must be `FALSE` (`openai/R/create_chat_completion.R:116-118, 209`) | Raw lists | – | – | – | – | Abandoned since 2023-03. VERIFIED |

---

## 11. Other packages from track 10

- **ravel 0.1.4** is the only CLI "provider" on CRAN. It runs
  `system2(binary, c("exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", "--output-last-message", f, "-"), stdin = prompt_file)`
  (`ravel/R/providers_openai.R:222-245`). The call blocks. The whole conversation is flattened into one prompt
  by `ravel_cli_provider_prompt()`. It produces no events and keeps no session. VERIFIED.
- **vitals 0.4.0** runs `claude_code()` / `codex()` solvers inside Docker through Python Inspect
  (track 10 §2.7). That is not an R-native provider. VERIFIED (track 10).
- **tidyprompt 0.4.0** needs runtime shims to work with ellmer (`tidyprompt/R/llm_providers.R:1008-1028`),
  evidence of coupling costs. **mcplite 0.1.0** re-implements ellmer's `tool()` / `type_*()` DSL, so the
  vocabulary is a convention (track 10 §2.7). **LLMR** and **rtemis.llm** extract logprobs, the only
  probability source for emulated System 1 on OpenAI-style providers (track 10 §2.7). **shinychat** is a UI
  over ellmer. VERIFIED (track 10, re-read).

---

## 12. Cross-package matrix (✓ has it, ~ partial or flawed, ✗ absent; evidence in sections 3–11)

| Capability | ellmer | tidyllm | btw/mcptools | corteza+llm.api | aisdk | agenticr | chattr/mall | rollama |
|---|---|---|---|---|---|---|---|---|
| Incremental sync streaming | ✗ (E1) | ✗ LIKELY | ✗ (ellmer) | ✗ (non-stream agent) | ✗ LIKELY | ~ (httr, byte-unsafe) | ✗ (ellmer) | ✗ LIKELY |
| Incremental async streaming | ✓ (promises; blocks until headers, V-8) | ✓ (`send_chat`) | – | ✗ | ✗ | ✗ | ~ | ✗ |
| Tool-call deltas surfaced | ✗ | ✗ | ✗ | ✗ | ✗ (accumulated silently) | ✗ | ✗ | ✗ |
| Interrupt → steer/continue | ✗ | ✗ | ✗ | ~ (repair after abort) | ✗ | ✗ | ✗ | ✗ |
| Idle (not total) timeout | ✗ (300 s total) | ~ (blocked) | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| Retry-After honoured and capped | ~ (no cap) | ~ | ~ | ✗ | ~ (no cap) | ✗ | ~ | ✗ |
| Provenance per message | ✗ | ~ (meta) | ✗ | ✗ (native) | ? | ✗ | ✗ | ✗ |
| Redacted / encrypted reasoning | ~ (redacted aborts) | ~ | ~ | ~ (native) | ✗ | ✗ | ✗ | ✗ |
| Cross-provider hand-off | ✗ (E12) | ✗ | ✗ | ✗ | ? | ✗ | ✗ | ✗ |
| Images in tool results (native) | ✗ (unrolled) | ✗ | ✗ | ? | ? | ✗ | ✗ | ✗ |
| Argument validation | ✗ (E9) | ✗ | ✗ | ✗ | ? | ✗ | – | – |
| Never-throw tool dispatch | ~ (interrupts, callbacks escape) | ✗ | ~ | ~ (no `is_error`) | ? | ~ | – | – |
| Approval hook | ~ (deny only; prompting ad hoc in the callback) | ✗ | ✗ | ✓ (modes) | ~ (boolean) | ~ | ✗ | ✗ |
| `max_turns` | ✗ | ✓ (10, then error) | ✗ | ✓ (20) | ✓ (`max_steps`) | ~ (token budget) | – | – |
| Steering / follow-up queues | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Append-only transcript | ✗ | ✗ | ✗ | ✓ (flat v2) | ✓ (console only) | ✗ | ✗ | ✗ |
| Message tree / fork | ✗ | ✗ | ✗ | ✗ | ~ (branches) | ✗ | ✗ | ✗ |
| No global run state | ✗ | ~ | ✗ | ~ | ? | ✗ | ✗ | ✗ |
| In-process concurrent agents | ~ (async only) | ~ (tools block) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Caller-environment evaluation | – | – | ✗ (global) | ✗ (global) | ~ (in-process own/supplied env; subprocess `r_eval`) | ✗ (global) | ✗ | – |
| System 1 with probabilities | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ (factor, NA) | ~ (logprobs) |
| Subscription CLIs | ✗ | ✗ | ✗ | ✗ (OAuth, ToS) | ✗ | ✗ | ✗ | ✗ |
| Cost with cache TTLs and reasoning | ~ (3 numbers) | ~ | ~ | ✓ (TTL split) | ? | ~ | ~ | ✗ |

`?` = not established from the parts of the source read (large codebase); treat as UNCERTAIN.

---

## 13. Synthesis: capability → best existing R package → its limitation → what gptr must do instead

| Capability | Best existing R package | Its limitation (evidence) | What gptr's own infrastructure must do |
|---|---|---|---|
| HTTP transport for streams | ellmer async (`later_fd`) / tidyllm `send_chat` | Needs promises + coro + later; the sync path, used at the console, is not incremental (E1, E2); coro costs 2–3× the CPU (report 15 §2.3) | One gptr-owned curl-multi reactor with `pipewait = 0`, used for console, scripts and background alike (INFRA-01, INFRA-16) |
| Normalised stream events | tidyllm `stream_event(kind)` | Text, thinking, error and done only; no tool-call deltas; no message start or end; errors are thrown | Pi-style protocol: start; text/thinking/toolcall start/delta/end; done or error, with the partial message; plus agent events (INFRA-02) |
| Cancel / interrupt / steer | ellmer `stream_controller` + partial turns; corteza repair | Checked between events only; Ctrl-C escapes; partial lost; misreported tool state (E3) | Resume-restart interrupt menu, abort that cancels the transfer, steering queue (INFRA-03, INFRA-04, INFRA-12) |
| Timeouts | aisdk (connect / first byte / idle / total, as libcurl options) | aisdk's layering is sound and works under blocking reads, but it sits on aisdk's blocking transport (§8); tidyllm's R-level idle check cannot fire under blocking reads; ellmer's is total (E4) | Connect, first-byte and idle limits enforced by the reactor clock (or libcurl options, as aisdk does); no total limit on streams by default (INFRA-05) |
| Retries | httr2 `req_retry` (ellmer) | Uncapped Retry-After; mid-stream overloads not retried (E5, E8) | Error classification, capped backoff with jitter honouring retry-after(-ms), interruptible waits, mid-stream restart before any delta is committed, agent-level retry (INFRA-06) |
| Message model | ellmer Turn/Content | No provenance field (raw `@json` only); redacted thinking aborts; text-only tool results; one-string system prompt (E6; `turns.R:129-150`) | Provider-neutral blocks with provenance and byte-exact opaque replay fields; images in tool results; system-prompt sections (INFRA-07) |
| Cross-provider hand-off | – (ellmer `set_turns` into another Chat) | Emits invalid items and drops encrypted content (E12) | One transform per target: same model keeps signatures; foreign thinking becomes text; opaque data dropped; ids normalised; orphans get results (INFRA-08) |
| Tool schema and validation | ellmer `tool()` + `type_*()` | No validation: missing required → `NA`, wrong types pass (E9) | JSON-Schema validation before dispatch; errors returned to the model (INFRA-09) |
| Tool dispatch | ellmer `invoke_tool` | Interrupts and callback errors escape; tidyllm throws; llm.api has no `is_error`; a truncated call aborts (E10) | Never-throw dispatcher; `length` stops fail calls unrun; source-order results; sequential and parallel modes (INFRA-10) |
| Approval | ellmer `on_tool_request` + `tool_reject`; aisdk `on_tool_approval` | Deny is the only structured outcome (asking is ad hoc inside the callback); arguments cannot be modified; no built-in modes; aisdk's is boolean | A permission hook returning allow / deny(reason) / ask / modify(args); modes plan, manual, edits, auto (INFRA-11) |
| Loop control | llm.api `agent(max_turns)` | No steering or follow-up; ellmer has no limit and cannot be stepped | gptr-owned Pi loop with `max_turns`, queues, turn hooks and a stepwise API (INFRA-12) |
| Persistence | aisdk console log / corteza JSONL | Flat or branch-level; RNG-consuming ids; snapshot saves elsewhere | Append-only JSONL v3 tree (`id` / `parentId`), crash-safe appends, resume, branch, fork (INFRA-13) |
| Session object for the native pipe | ellmer R6 `Chat` | Shallow clone shares callbacks (E13); tidyllm pipes create new values | Environment-backed S3 session; explicit fork that copies state, never callbacks or connections (INFRA-14) |
| Many agents in one session | ellmer async API | Global usage summary (per-chat usage exists) and a global tool-context stack (E13); the async path blocks during TTFT (V-8); `parallel_chat` lock-step | Per-agent state machines; no package-global run state (INFRA-15, INFRA-16) |
| Sub-agents | btw (in-process, synchronous) / corteza (`callr`) | Blocking the parent; in-memory registry | Inline, worker and CLI modes in the one reactor; the parent parks in `waiting_children` (INFRA-16, report 15) |
| Provider extension | tidyllm S7 generics / ellmer non-exported generics | Unstable internals; no new *kinds* | Data-driven providers plus a few wire adapters behind an exported, versioned S3 contract (INFRA-17) |
| System 1 | mall (factor) / LLMR (logprobs) | No probabilities; `NA` coercion | A provider kind `classify` that returns typed, vectorised values with probabilities (INFRA-18) |
| Subscription plans | ravel (`system2`) / llm.api (OAuth) | Blocking and flattened; OAuth against the terms | `claude -p --output-format stream-json` and `codex exec --json` through processx, normalised into the same events (INFRA-19) |
| Cost and usage | ellmer price table; llm.api TTL split | Three-number tokens; global aggregation; cancelled turns uncounted | A per-request usage record with cache writes by TTL, reasoning tokens and tiers, attributed to agent, provider and route (INFRA-20) |
| Rate limits | tidyllm header tracking | Global and informational | Per-provider limiter that feeds the reactor's admission control (INFRA-21) |
| Credentials | ellmer `credentials()` + redacted headers | – (good) | Keep the design; add `.env` aliases and redaction in transcripts and logs (INFRA-22) |
| Stream decoding | httr2 `resp_stream_sse` | 0.19 ms per event (report 21); agenticr byte-unsafe (E15); ellmer O(n²) accumulation (E14) | Byte-level SSE/NDJSON splitter; linear accumulation (INFRA-23) |
| Testing | ellmer (vcr) / aisdk (httptest2) | Recording-based; httpuv cannot stream (report 15 §2.1) | Fake provider, base-R mock SSE server, wire fixtures (INFRA-24) |
| Structured output | ellmer `chat_structured` | Turns tools off (`chat.R:416-419`) | Native schema output that can coexist with tools; emulated System 1 builds on it (INFRA-25) |
| Context management | ellmer `on_request_start` + `set_turns` (0.5.0) | A side-effecting hook; the pending turn is re-appended automatically | A loop-owned `transform_context` / projection plus compaction on overflow (INFRA-26) |
| Console rendering | ellmer `live_console` | A ~50-line `readline` loop; no interrupt, steering or slash commands; `echo` tied to transport | Renderer subscribes to events; transport knows nothing about the console (INFRA-27; report 18) |
| Observability | ellmer OTel spans | – (good, optional) | Event-derived wire log with redaction; optional OTel in Suggests (INFRA-28) |
| Evaluation environment | btw `run_r` (`evaluate`) | Global env; sticky references; no timeout | Caller environment, hand-rolled evaluator — report 12 (outside this layer; referenced by INFRA-10) |

---

## 14. REQUIREMENTS FOR GPTR'S OWN LLM INFRASTRUCTURE (INFRA-01..INFRA-28)

Each item gives the requirement, the evidence (the ecosystem limitation it answers), where the R
implementation is shown, and an acceptance test for the test suite. "Mock" means gptr's own base-R SSE
mock (report 15 §5.1; this report's `mock_anthropic.R` is a scenario-driven variant).

**INFRA-01 — Own incremental transport on a curl multi pool.** Every provider stream (HTTP) goes through
`curl::multi_add(data = callback)` driven by a gptr loop (`multi_run(timeout = 0)` + `processx::poll()` on
`processx::curl_fds(curl::multi_fdset(pool))`). Every handle sets `pipewait = 0L`. Nothing uses
`httr2::req_perform_connection()` for streaming, in blocking or non-blocking mode.
- *Evidence.* E1/E2: blocking httr2 reads deliver nothing until 64 KiB arrive (1.3.0) or in 1 KB bursts (1.2.2). The same call is used by ellmer's sync path, tidyllm, aisdk and rollama. PIPEWAIT serialises HTTP/1.1 streams (report 15 §2.2).
- *How.* Report 15 §2.2–2.4, §4.2, §5.2, §5.9; report 03 §5.4; report 09 §4.4.
- *Accept.* On the mock (12 events every 0.25 s), the first text delta reaches the event callback within 0.35 s of the server writing it, and every inter-delta gap is under 0.35 s. Six concurrent streams of 1.00–2.25 s finish within 10 % of the slowest stream.

**INFRA-02 — Normalised provider event protocol.** Every adapter (Anthropic, OpenAI Responses and Completions,
Gemini, CLI, System 1) emits the same event types: `start`; `text_start|delta|end`;
`thinking_start|delta|end`; `toolcall_start|delta|end`, carrying the incrementally parsed partial arguments;
then exactly one of `done(reason = stop|length|tool_use)` or `error(reason = error|aborted, partial)`.
Failures after `start` are **events, not conditions**. The agent layer adds `agent_start/end`,
`turn_start/end`, `message_start/update/end`, `tool_execution_start/update/end`, `queue_update` and
`retry_start/end`.
- *Evidence.* ellmer yields only text and thinking deltas and hides tool-argument deltas (`provider-claude.R:339-381`). Its errors are `cli_abort()` mid-stream (`provider-openai.R` merge; `provider-claude.R:425-434`). tidyllm has four kinds and throws on error.
- *How.* Report 03 §2.3, §3.2, §5.1–5.3; report 02 §2.4, §4.4.
- *Accept.* Fixture replays for each adapter produce the golden event sequence. A server-side error event and a truncated connection both yield exactly one `error` event carrying the partial message, and no R error escapes the adapter.

**INFRA-03 — Interrupt-safe streaming with resume, steer and abort.** A user interrupt at any phase
(connect, TTFT, body, tool execution) is caught by a calling handler that offers a menu through R's
`resume` restart (steer, follow-up, continue, abort). A second Ctrl-C aborts. Abort cancels the transfer
(`curl::multi_cancel`), kills child trees and records the partial message with `stop_reason = "aborted"`.
- *Evidence.* E3: in ellmer the interrupt always escapes, the partial is empty although deltas had arrived, and latency is 1.2–1.4 s on httr2 1.3.0. Track 02: only the curl-multi loop survives a *resumed* interrupt before the headers.
- *How.* Report 02 §5.4–5.5, §4.7–4.8; report 18 §2.2, §4.6; report 15 §2.11, §5.10.
- *Accept.* Scripted SIGINT during TTFT, mid-body and mid-tool gives, respectively: the request continues after "continue"; a queued steering message is delivered after the current turn; "abort" closes the socket (the mock logs the disconnect), the session stays usable, and the partial text equals what was received.

**INFRA-04 — Honest partial and failed turns, and request projection.** Every assistant message records
`stop_reason ∈ {stop, length, tool_use, aborted, error}` with an error message. Aborted and errored
assistant messages are **persisted but projected out** of the next request (Pi's rule). gptr never invents
assistant content (no "[empty string]"). An interrupted or aborted tool gets a synthetic result that says
what happened: "interrupted after 2.3 s; side effects may have occurred", never "not invoked".
- *Evidence.* E3: "[empty string]" replayed; the false "Chat ended before the tool could be invoked." E7: a 401 recorded as an "interrupted" partial. E5/E6/E10: every abnormal end is labelled "interrupted" (`chat.R:1425-1439`). corteza shows the honest alternative (`corteza/R/interrupt.R`).
- *How.* Report 02 §2.7, §2.9, §4.8; report 03 §2.9 (orphans).
- *Accept.* After a 401 the transcript records the failure (an entry with `stop_reason = "error"`), but the next request body contains no assistant content for it. After an abort, the next wire body contains no aborted assistant content, and every `tool_use` has exactly one result.

**INFRA-05 — Layered timeouts.** Connect timeout, first-byte (header) timeout and idle-between-bytes
timeout, enforced by the reactor's clock. **No total transfer timeout on streams** by default. An optional
per-run wall-clock budget belongs to the loop, not to the transport.
- *Evidence.* E4: ellmer's 300 s total limit (`httr2.R:120`) killed a live stream. tidyllm's idle deadline cannot fire under blocking reads (`stream_pump.R:118-120`). aisdk shows the layering, done with libcurl options that work even under blocking reads (`utils_http.R:226-318`: `connecttimeout`, `server_response_timeout`, `low_speed_limit`/`low_speed_time`, no total by default).
- *How.* Report 03 §1 item 17 (`connecttimeout` + `low_speed_time`); report 15 §3.7 constants; report 07 §2.11.
- *Accept.* A mock that holds the headers past the first-byte limit gives `error(reason = "error", class = "gptr_timeout_first_byte")`. A 10-minute stream sending one byte every 10 s completes. A stall longer than the idle limit gives an idle-timeout error.

**INFRA-06 — Retry with bounded backoff that honours Retry-After.**
- *Provider level.* Retry 408, 409, 429, 5xx, 529 and network errors, before any delta has been committed to the transcript. Honour `retry-after-ms`, then `retry-after`, **capped** by `max_retry_delay` (default 60 s; if the server asks for more, fail fast with the server's value in the error). Otherwise use `0.5 s × 2^i` with jitter, capped at 8 s. Waits are interruptible and emit `retry_start/end` events.
- *Mid-stream.* A provider error event (Anthropic `overloaded_error`) before any committed delta restarts the request.
- *Agent level.* Classify the error text (report 02) and retry with a fresh request.
- *Evidence.* E5: ellmer sleeps, then fails with "Connection closed unexpectedly". E8 plus printed httr2 source: Retry-After is uncapped. aisdk's own loop is uncapped too (`utils_http.R:612-633`).
- *How.* Report 02 §2.8, §3.7, §5.3; report 03 §2.15; report 04 §2.6 (System One retry behaviour).
- *Accept.* On the mock: 429 + `retry-after: 2` retries after about 2 s. `retry-after: 3600` fails at once with a classed error that states the delay. An overload event before the first delta is retried transparently. An overload after deltas is surfaced as an `error` event with the partial.

**INFRA-07 — Provider-neutral message model with provenance and byte-exact opaque data.**
- *Messages.* S3 list classes for `system` (named, independently replaceable sections), `user`, `assistant` (blocks plus `api`, `provider`, `model`, `response_id`, `usage`, `stop_reason`, `error_message`), `tool_result` (`tool_call_id`, `tool_name`, text **and image** blocks, `is_error`, R-side `details` never sent to the model), and custom roles (steering, `r_execution`, compaction summaries) converted just before the request.
- *Blocks.* `text` (+ `text_signature`), `thinking` (+ `thinking_signature`, `redacted`), `image`, and `tool_call` (+ `thought_signature`; the provider id kept verbatim, e.g. `call_id|item_id`).
- *Round trip.* Opaque strings are stored and replayed **byte for byte**. jsonlite settings follow report 02 §5.9: `auto_unbox`, `null = "null"`, `digits = NA`, `simplifyVector = FALSE`.
- *Evidence.* ellmer has no provenance field, only the raw `@json` (`turns.R:129-150`), aborts on redacted thinking (E6), has text-only results with image unrolling (`chat-tools-content.R`), and a one-string system prompt (`chat.R:165-181`). tidyllm keeps only the first thinking block, in metadata (`api_claude.R:173-197`).
- *How.* Report 03 §2.2, §3.1, §4.2, §5.5; report 07 §2.5–2.6; report 08 §3.2; report 09 §2.1.
- *Accept.* Golden fixtures, each round-tripping to a byte-identical re-serialisation on replay to the same model: an Anthropic stream with `thinking` + `signature_delta` + `redacted_thinking` + a parallel `tool_use`; OpenAI Responses with an encrypted reasoning item and `fc_`/`call_` ids; Gemini with a `thoughtSignature`. A tool result holding a PNG is sent as a native image block to Anthropic and OpenAI Responses.

**INFRA-08 — Cross-provider hand-off transform.** A single function `gptr_transform_messages(messages, target)`,
applied just before every request:
- if the source is the same model, keep signatures and encrypted items;
- otherwise, thinking becomes plain text (or is dropped by policy), redacted or encrypted data and thought signatures are dropped, tool ids are normalised to the target's rules, errored or aborted turns are skipped, and orphaned calls get a synthetic "No result provided" error result.
- *Evidence.* E12: ellmer produced `{"signature":…}` and `"signature":{}` items and lost `encrypted_content`.
- *How.* Report 03 §2.9, §3.5, §5.5 (R prototype).
- *Accept.* A conversation built on Anthropic (thinking + tools) and continued on OpenAI Responses and on Gemini produces request bodies that validate against each provider's schema fixture and contain no foreign opaque fields.

**INFRA-09 — Tool-call protocol with validation.**
- Tool definitions carry a JSON Schema: from R formals, from a small `type_*`-like vocabulary compatible with ellmer's (credit), or from MCP.
- Arguments are parsed incrementally while streaming (a partial-JSON scanner) and **validated before dispatch**: required fields, types, enums, `additionalProperties`. Coercion is explicit and never produces a silent `NA`.
- A turn that stopped for `length` or `refusal` never executes its tool calls; each gets an error result.
- *Evidence.* E9: a missing required argument became `NA` and wrong types passed. E10: a truncated call aborted the whole run. tidyllm parses with `simplifyVector = TRUE` (`api_chat_completions.R:171-176`).
- *How.* Report 03 §2.8, §3.5, §5.2 (incremental partial JSON); report 02 §2.3; report 07 lines 255-277; report 21 §2.7.
- *Accept.* `{"n":3}` against a schema that requires `code` gives an `is_error` result "missing required argument `code`" and the function is not called. A `max_tokens` stop with a half-streamed call gives an error result, a `done(reason = "length")` event, and no R error.

**INFRA-10 — Never-throw tool dispatcher.**
- Unknown tool, validation failure, permission denial, an R error, an R warning under `warn = 2`, a timeout and an **interrupt** during a tool all become a `tool_result` with `is_error = TRUE` and one text block. The loop never unwinds through the dispatcher.
- Results keep source order.
- Execution mode per tool: the `r` tool is sequential (one tool FIFO on the main thread); read-only I/O tools may run in parallel; one sequential tool makes the whole batch sequential (Pi).
- Results carry model text plus optional images, and R-side `details`: the R value, used by `$value` and `gptr_return()`.
- *Evidence.* ellmer: interrupts and callback errors escape (E3; `chat-tools.R:282-295`). tidyllm: bare `do.call` (`api_chat_completions.R:171-221`). llm.api: no `is_error`. ellmer's results are text-only.
- *How.* Report 02 §2.3, §4.10; report 12 §3.1–3.4 (the `r` tool and its result format); report 15 §2.3 (tool FIFO).
- *Accept.* A property test: throw, interrupt, warn-as-error and a 30 s timeout inside tools. Each run completes with matching `tool_result`s, the transcript validates, and each `tool_execution_end` event is paired with its start.

**INFRA-11 — Permission and approval hooks.**
- `before_tool_call(call, context)` returns `allow`, `deny(reason)`, `ask(question)` or `modify(args)`. `after_tool_call` may rewrite the result.
- Modes `plan`, `manual`, `edits`, `auto` sit on top, using the advisory R risk classifier.
- A denial reaches the model as an error result carrying the reason. It never aborts the loop.
- The prompt uses the UI abstraction and **fails closed** when no UI exists: never `askYesNo()`.
- *Evidence.* ellmer's only structured outcome is deny, through a classed condition (`tools-def.R:468-478`). Asking is done ad hoc inside the callback (its own example blocks on `utils::menu()`, `tools-def.R:439-453`), and the callback cannot modify arguments. aisdk's `on_tool_approval` is boolean. There are no built-in modes in ellmer or btw.
- *How.* Report 18 §3.7, §4.7, §2.6; report 02 §2.12, §4.5.
- *Accept.* The 11-row mode × risk matrix of report 18 passes. `modify` changes the arguments seen by the tool and recorded in the transcript. A denial is recorded with its reason.

**INFRA-12 — A gptr-owned agent loop with steering and follow-up queues.**
- Pi's two nested loops, stateless in R.
- A steering queue is polled at the loop start, after each `turn_end` and after tool preflight. A follow-up queue is polled when the agent would otherwise stop.
- `max_turns` (default finite, e.g. 50).
- Stop conditions as in Pi. A stepwise API (`gptr_step()`) serves the reactor and tests.
- Hooks: `transform_context`, `before/after_tool_call`, `finish_turn`, event listeners.
- Steering messages are placed **after** the complete tool-result message, so no provider ordering rule is broken.
- *Evidence.* ellmer: no limit, not steppable (track 10 prototypes), no queues. The hook-based injection broke tool-result ordering (E11). No package has a steering feature (the only "steer" match is an unrelated mcptools comment).
- *How.* Report 02 §2.2, §2.6, §4.1–4.3, §4.7, §4.11, §5.1 (a 540-line base-R loop, 24 checks).
- *Accept.* Report 02's 24 loop checks, plus: a steering message enqueued during a tool is delivered as a user message after the tool-result message on the wire, and `max_turns = 3` stops with a classed `gptr_max_turns` result.

**INFRA-13 — Append-only session store.**
- One JSONL file per session tree (Pi v3: a header line, then entries with `id` / `parentId`) under `.gptr/sessions/` (D-09/D-10).
- Every message, model change, compaction and branch is **appended** at `message_end` inside `suspendInterrupts()`, flushed, with LF line endings.
- Ids are generated without touching the user's RNG.
- Resume = rebuild the context from leaf to root; branch = move the leaf; fork = copy one path into a new file whose header names its parent.
- *Evidence.* ellmer keeps a mutable in-memory list (U9). tidyllm drops tool rounds. aisdk ids consume `.Random.seed` (`session_event_store.R:50, 141`). corteza's JSONL is flat.
- *How.* Report 02 §2.11, §3.4, §4.6, §5.2, §5.8–5.9; report 12 (RNG); report 15 §5.12.
- *Accept.* Kill the R process (SIGKILL) during a streamed turn; after resume the file parses, the last complete message is present, and nothing is duplicated. `identical(.Random.seed)` holds before and after 1,000 appends. A forked file replays to the same context as its source path.

**INFRA-14 — Session object semantics for `|>`.** `gptr()` returns an environment-backed S3 session (S-8,
D-05). Piping appends to the same session. `gptr_fork()` creates a new session, copies state and the
transcript path lineage, and **never shares** listeners, queues, connections or processes. Printing shows
the last answer. `$value` holds the R value.
- *Evidence.* ellmer's shallow clone shares `CallbackManager`s (E13). tidyllm's pipe creates new values, so no shared session exists.
- *How.* Report 12 §2.E, §3.10; report 02 §4.1.
- *Accept.* `s2 = gptr_fork(s)`; a listener added to `s2` never fires for `s`; both sessions append to different leaves.

**INFRA-15 — No package-global mutable run state.** Usage, tool context, queues, abort handles,
rate-limit views and caches of in-flight state live in the agent or session objects. Package-level
environments hold only immutable configuration, registries and the model catalogue. Process-wide views
(`gptr_usage()`) are *computed* by aggregating live sessions and store files.
- *Evidence.* ellmer's process-wide `the$tokens` summary merged two chats (E13; by design, and per-chat `$get_tokens()` stays correct), and it keeps `the$tool_context_stack`. chattr's `ch_env`, rollama's `the$prompts`, mall's `.env_llm` and btw's `.btw_subagent_sessions` do the same.
- *How.* Report 15 §4.2, §4.11.
- *Accept.* Two sessions with the same model run concurrently in one process; each session's usage equals the sum of its own requests; tool context inside interleaved tools is correct.

**INFRA-16 — One reactor for many streams and child processes.**
- A single loop owns all HTTP streams (INFRA-01), `callr` workers and CLI agents (`processx` pipes) and waits with one `processx::poll()`.
- Each agent is a state machine: `queued`, `streaming`, `tools`, `ready`, `waiting_children`, `done`, `error`.
- Tool calls go through one FIFO on the main thread. `max_active` provides admission control.
- Background mode is serviced by `later` when the console is idle.
- `parallel` means independent state machines, not lock-step rounds.
- *Evidence.* `parallel_chat()` is lock-step, non-streaming and sequential in its tools (`parallel-chat.R:66-141, 329`). btw sub-agents are synchronous. tidyllm's tool loop blocks.
- *How.* Report 15 §2.3–2.5, §4.2–4.7, §5.4, §5.9, §5.14.
- *Accept.* Report 15's `p10_mixed` shape: two inline, two worker and one CLI agent interleave within one wall time close to the slowest agent. Tool calls never overlap.

**INFRA-17 — A provider adapter contract that is data plus a few wire adapters.**
- A provider is a record: id, base URL, headers, auth resolver, `compat` flags, catalogue entries.
- It binds to one of a closed set of wire adapters: `anthropic-messages`, `openai-responses`, `openai-completions`, `google-generative-ai`, `typesafe-system-one`, `cli-claude`, `cli-codex`.
- Extensions register providers (and, rarely, adapters) through an **exported, versioned S3 interface** (REQ-29) documented as stable.
- *Evidence.* ellmer's generics are not exported and changed signature between minor versions (track 10 §5.8). Downstream packages need shims (`tidyprompt/R/llm_providers.R:1008-1028`; `ellmer/R/turns.R:52-55`).
- *How.* Report 03 §2.1, §2.4, §4.1–4.3; report 09 §3.3, §4.1–4.3.
- *Accept.* An OpenAI-compatible provider (e.g. local Ollama) is added by data alone. An extension-registered fake provider passes the adapter conformance suite (INFRA-24).

**INFRA-18 — System 1 as a first-class model type.**
- A separate adapter kind `classify(model, questions, state)` → answers with probabilities and confidence, returning typed R vectors (`gptr_decision` logical + `prob`; a choice factor with a probability matrix; a score with confidence).
- Vectorised, with concurrent requests on the reactor, an explicit abstention policy (`na_below`, `stop_below`), and emulation through structured output or logprobs when no key is present.
- *Evidence.* No package integrates it. mall returns factors, coerces invalid answers to `NA` and has no probabilities (`m-vec-prompt.R:33-55`). LLMR and rtemis.llm have logprobs only.
- *How.* Report 04 §2.2–2.4, §4.3–4.8; report 03 §2.14; decision register D-06.
- *Accept.* `if (gptr("…", x, model = jev))` works on a mocked `/systemone`; vectorised input of 100 items issues concurrent requests, capped by `max_active`; below-threshold behaviour follows the policy.

**INFRA-19 — Subscription CLIs as providers.**
- `claude -p --output-format stream-json --verbose --include-partial-messages` and `codex exec --json` (or the Codex app-server) run under `processx`, with the prompt on stdin and the write-all loop.
- Their JSONL events are normalised into INFRA-02 events and usage.
- Cancel with SIGINT first, then `kill_tree()`. `--permission-mode` is passed explicitly.
- Never broker Claude.ai OAuth. Sessions continue via the CLI's own session id rather than by flattening the history into one prompt.
- *Evidence.* ravel blocks on `system2()`, flattens the history and runs `--ephemeral` (`providers_openai.R:222-245`). vitals needs Docker and Python. llm.api's Claude OAuth conflicts with Anthropic's terms.
- *How.* Report 07 §2.13–2.16, §4.3; report 08 §2.E–2.F, §4.4, §5.1–5.4; report 15 §2.9, §5.15.
- *Accept.* With the fake-CLI fixtures from report 15, three concurrent CLI agents stream events into the reactor; an abort leaves no surviving process tree; usage and cost fields are populated.

**INFRA-20 — Usage and cost accounting by provider and route.**
- Every request records input, output, cache read, cache write (5 min and 1 h separately), reasoning tokens, the request-wide pricing tier and cost.
- Each record is attributed to session, agent, provider, model and **route** (`api`, `plan-cli`, `system-one`, `emulated`).
- Aborted and errored requests are counted when the provider reported usage.
- Prices come from a shipped catalogue snapshot with a `schema_version`, refreshed only on request into `R_user_dir`.
- *Evidence.* ellmer's tokens are three numbers; cancelled turns are not logged (`tokens.R:53-58`); its Anthropic cache-write surcharge is a flat 0.25 (`provider-claude.R:536-540`) even when `cache = "1h"` was requested (1-hour writes cost 2×); per-chat usage exists, but the cross-chat summary is keyed only by provider and model (E13). llm.api shows the TTL split.
- *How.* Report 03 §2.7, §3.4; report 07 §3.5; report 08 §3.7; report 09 §4.8; report 15 §4.11.
- *Accept.* The fixture usage for a turn with 1 h cache writes gives the documented dollar amount; the per-agent sum equals the session total; the route appears in `gptr_usage()`.

**INFRA-21 — Rate-limit awareness.** Parse the provider rate-limit headers (Anthropic `anthropic-ratelimit-*`,
OpenAI `x-ratelimit-*`) into a per-provider limiter owned by the reactor. The limiter gates admission of new
requests from concurrent agents (requests and tokens per minute) and exposes the state in events.
- *Evidence.* tidyllm's tracking is global and informational only (`rate_limits.R`). ellmer throttles `parallel_chat` by rpm and Mistral requests to 1 per second (`provider-mistral.R:90-98`), and reads no Anthropic or OpenAI rate-limit headers.
- *How.* Report 07 §2.11, §3.4; report 08 §2.D, §3.5; report 15 §4.6.
- *Accept.* With the mock returning low remaining-request headers, a fan-out of 20 agents never exceeds the advertised budget and never sleeps inside an HTTP callback.

**INFRA-22 — Credentials never stored.** Keep ellmer's design (credit): a resolver function per provider,
evaluated per request, with headers added through a redacted mechanism. Add `.env` loading with aliases
(`jev-key` → `TYPESAFE_API_KEY`, REQ-13) and redaction of secrets in transcripts, wire logs, error messages
and printed request objects.
- *Evidence.* `ellmer/R/utils-auth.R:47-87` shows the pattern. gptstudio and agenticr put keys into header lists directly (`gptstudio/R/service-openai_streaming.R:26-29`; `agenticr/R/llm.R:149-151`).
- *How.* Report 03 §2.11, §4.5; D-22.
- *Accept.* Grep the session file, the wire log and `format(request)` after a keyed run: no key bytes.

**INFRA-23 — Byte-level, linear-time stream decoding.** Split SSE and NDJSON on **raw bytes**, carrying the
incomplete tail. Decode each complete event with `rawToChar()` and mark it UTF-8. Accumulate deltas in
preallocated lists joined once; never `paste0` per delta, never an S7 or validator per delta. The per-delta
cost must be O(1) amortised.
- *Evidence.* E14: ellmer 0.5.0 took 14–18 s for 2,000 deltas, and ellmer itself uses `paste<-` (`utils.R:115-117`). E15: string-level splitting breaks on split UTF-8 (agenticr). httr2's SSE parser costs 0.19 ms per event (report 21 §1).
- *How.* Report 03 §5.1; report 21 §2.6 (vectorised splitter, 23–29 µs per event); report 19 §2.4.2.
- *Accept.* 20,000 deltas are consumed in under 1 s of CPU. Randomly re-chunked byte streams, including splits inside multi-byte characters, give identical events (report 18's chunk-invariance style test).

**INFRA-24 — Testability: fake provider, mock server and wire fixtures.**
- (a) A built-in fake provider that emits scripted INFRA-02 event sequences, for loop, tool, queue and store tests with no network.
- (b) A base-R mock SSE server (serverSocket + socketSelect, runs in `callr`) with scenario paths like this report's (slow, TTFT, overload, redacted, 401, 429, truncated, parallel tools).
- (c) Wire fixtures per adapter: request body plus raw SSE transcript, replayed byte-exact through the real adapter.
- (d) An adapter conformance suite that every provider, built-in or extension, must pass.
- All network tests `skip_on_cran()`.
- *Evidence.* ellmer depends on vcr recordings (Suggests), aisdk on httptest2. httpuv cannot stream (report 15 §2.1). This report's 16 experiments show how much behaviour only a scenario mock exposes.
- *How.* Report 15 §2.1, §5.1; report 02 §5.1; report 10 §5.2; this report, Appendix A.1.
- *Accept.* The whole INFRA suite runs offline under `R CMD check --as-cran` in under 60 s.

**INFRA-25 — Structured output that coexists with tools.** Native JSON-schema output where the model
supports it; a forced-tool fallback otherwise (credit ellmer). Structured turns must not disable the agent's
tools by default. System 1 emulation uses this path.
- *Evidence.* ellmer's `chat_structured()` turns tools off (`chat.R:416-419`) and cannot stream the tool fallback (`chat.R:760-769`).
- *How.* Report 07 §2.3, §2.5; report 08 §3.1; report 04 §2.12.
- *Accept.* A run with tools plus `type =` returns the typed value and a transcript that still contains the tool calls.

**INFRA-26 — Loop-owned context management.** `transform_context(messages) → messages` runs before every
request (projection, truncation of large tool outputs with a spill file, image policy). Overflow is detected
from the error text or from usage, then compacted and retried exactly once. Compaction entries are appended
to the store, never rewriting it.
- *Evidence.* ellmer's `on_request_start` + `set_turns()` is a side-effecting workaround, and the pending turn is re-appended automatically (`chat.R:699-715`). agenticr's hard truncation drops leading tool messages (`llm.R:304-318`).
- *How.* Report 02 §2.9–2.10, §3.5, §4.9; report 21 §2.8 (token estimates).
- *Accept.* A mock returning a context-overflow error triggers one compaction and one retry; the store holds a compaction entry; a second overflow surfaces as an error.

**INFRA-27 — Rendering decoupled from transport.** The console, knitr, Jupyter and Shiny renderers
**subscribe to events**. The transport and loop never print. The streaming markdown renderer gives the same
output however the stream is chunked. Verbosity depends on the front end.
- *Evidence.* In ellmer, `echo` selects the *transport*: `stream = echo != "none"` (`chat.R:406`), and display happens after the turn completes (`chat.R:36-37`). `live_console()` is a ~50-line `readline` loop with no interrupt handling (`ellmer/R/live.R:22-69`). gptstudio's streaming requires Shiny.
- *How.* Report 18 §2.1.7, §4.3–4.5, Appendix A.6.
- *Accept.* The same run produces byte-identical transcripts with verbosity 0, 1 and 2; only rendering differs.

**INFRA-28 — Observability.** An opt-in wire log built from events, with request bodies redacted per INFRA-22,
written to a session-scoped file. Optional OpenTelemetry spans following the `gen_ai` conventions (credit
ellmer's `otel.R`), with `otel` in Suggests only.
- *Evidence.* In this review, wire-level logging (the mock's `requests.jsonl`) was what revealed "[empty string]", misplaced steering and invalid hand-off items. ellmer shows a workable OTel mapping.
- *How.* Report 13 (Suggests policy); ellmer `R/otel.R` (design reference).
- *Accept.* With the option on, one JSONL line is written per request and per terminal event, with no secrets.

---

## 15. Borrow list with attribution (ideas; if code is ported, keep the MIT notice of the source)

| Idea | From | Where it lands in gptr |
|---|---|---|
| Credentials as zero-arg functions; redacted headers | ellmer (`R/utils-auth.R`) | INFRA-22 |
| Partial turn kept with a reason; reusable cancellation token | ellmer (`AssistantPartialTurn`, `stream_controller`) | INFRA-03, INFRA-04 |
| Tool error → result sent back to the model | ellmer (`invoke_tool`); Pi | INFRA-10 |
| Denial as a classed condition | ellmer `tool_reject()` | INFRA-11 (R API sugar for `deny()`) |
| MCP-style tool annotations; `type_*` vocabulary | ellmer; mcplite | INFRA-09 |
| `store = FALSE` + encrypted reasoning; cache breakpoints | ellmer providers | INFRA-07 |
| litellm price table with `schema_version` in `R_user_dir` | ellmer `R/prices.R` | INFRA-20 |
| Resumable batch state file keyed by a hash | ellmer `batch_chat()` | future batch API |
| OTel spans | ellmer `R/otel.R` | INFRA-28 |
| Stream pump separating transport, parse and sink; typed event kinds | tidyllm 0.6.0 | INFRA-02, INFRA-27 |
| Idle-not-total deadlines; "no terminal event is an error" | tidyllm; aisdk | INFRA-05 |
| Job handle vocabulary (`check`, `fetch`, `cancel`, `get_partial`); `.dry_run` | tidyllm | background agents; tests |
| Rate-limit header parsing | tidyllm | INFRA-21 |
| Small tool texts; cwd restriction; hash-anchored edits; opt-in dangerous tools | btw | tool layer (reports 11, 12) |
| Resumable sub-agent session ids | btw | sub-agents (report 15) |
| Live session serviced when idle; MAC-sealed IPC | mcptools | gptr MCP server (report 16) |
| Honest repair of interrupted tool histories | corteza | INFRA-04 |
| History callback after every message | llm.api | INFRA-13 |
| Cache-write TTL split in cost | llm.api | INFRA-20 |
| Layered timeouts; `retry-after-ms` | aisdk | INFRA-05, INFRA-06 |
| Branch-aware append-only event log | aisdk | INFRA-13 (with a message-level tree) |
| Explicit "data will be sent externally" notices | chattr | context attachment UX |
| Vectorised verbs over data frames with a response cache and `preview =` | mall | System 1 vectorisation (INFRA-18) |
| Logprob-based probabilities | rollama, LLMR, rtemis.llm | emulated System 1 |

---

## 16. Risks, pitfalls, open questions

1. **Snapshot findings.** httr2 1.3.0's 64 KiB blocking read and ellmer 0.5.0's quadratic accumulator are
   properties of today's CRAN versions and may be fixed. The case for owning the layer rests on control of
   the loop, the message model and interrupts (U2, U6–U11), not on any single bug. The two performance
   findings show why a dependency's regressions become gptr's.
2. **Local, plain-HTTP mock.** All streams went to a local HTTP/1.1 mock. That HTTPS / HTTP-2 providers
   batch the same way under blocking httr2 reads is LIKELY, because the mechanism is in the R connection
   read, but it was not tested live (no paid calls). The same caveat applies to the 1.2–1.4 s interrupt
   latency seen with httr2 1.3.0 (cause UNCERTAIN).
3. **Provider breadth.** ellmer covers 21 usable provider constructors, including enterprise auth
   (Bedrock SigV4, Vertex, Azure AD, Databricks, Snowflake). gptr v1 will cover fewer. Mitigation: the
   OpenAI-compatible adapter plus data-driven `compat` flags (report 09) cover most hosts. SigV4 in pure R
   is prototyped (report 09 §5.3).
4. **Do not repeat their mistakes.** Avoid S7 or R6 validators on hot paths (E14), string-level stream
   splitting (E15), `stats::runif()` ids, package-global run state, `askYesNo()` for permissions (report 18)
   and writes to the project directory without consent (report 13).
5. **Steering placement across providers.** INFRA-12 requires steering after the tool-result message.
   Whether every OpenAI-compatible host accepts a `user` message immediately after `tool` messages is
   UNCERTAIN. Test per host in the conformance suite.
6. **Duplicate tool results.** Which providers reject two results for one call id is still UNCERTAIN
   (track 10). INFRA-04 avoids the question by construction.
7. **ellmer's Responses tool ids.** Whether storing the `fc_` item id as `call_id` has wire consequences is
   UNCERTAIN (section 3.2). gptr keeps both ids regardless.
8. **aisdk and corteza coverage.** Only the parts relevant to infrastructure were read (42k and 20k lines).
   The `?` cells in section 12 are UNCERTAIN.
9. **Licensing.** All reviewed packages are MIT except rollama (GPL-3) and corteza (Apache-2). Borrow ideas
   from GPL-3 code only, never code.

---

## 17. Sources

Local package sources (MD5-verified CRAN tarballs, extracted to `$S`):
- ellmer 0.5.0: `R/chat.R`, `R/httr2.R`, `R/chat-tools.R`, `R/chat-tools-content.R`, `R/stream-controller.R`, `R/turns.R`, `R/content.R`, `R/content-replay.R`, `R/provider.R`, `R/provider-claude.R`, `R/provider-openai.R`, `R/provider-google.R`, `R/provider-openai-compatible.R`, `R/parallel-chat.R`, `R/batch-chat.R`, `R/live.R`, `R/tokens.R`, `R/prices.R`, `R/tool-context.R`, `R/tools-def.R`, `R/chat-structured.R`, `R/utils.R`, `R/utils-S7.R`, `R/utils-auth.R`.
- tidyllm 0.6.0: `R/perform_api_requests.R`, `R/stream_pump.R`, `R/async_chat.R`, `R/chat_pipeline.R`, `R/tools.R`, `R/api_chat_completions.R`, `R/api_claude.R`, `R/LLMMessage.R`, `R/rate_limits.R`.
- btw 1.5.0: `R/btw_client.R`, `R/tool-run.R`, `R/tool-agent-subagent.R`, `R/tool-files-read.R`. mcptools 1.0.3: `R/session.R`, `R/server.R`, `R/socket-auth.R`.
- corteza 0.7.1: `R/turn.R`, `R/interrupt.R`, `R/session.R`, `R/handles.R`, `R/tool-impl.R`, `R/schema.R`, `R/subagent.R`. llm.api 0.1.9: `R/agent.R`, `R/chat.R`, `R/cost.R`, `R/openai-codex.R`, `R/anthropic-claude.R`.
- aisdk 1.4.12: `R/utils_http.R`, `R/core_api.R`, `R/hooks.R`, `R/session.R`, `R/session_event_store.R`, `R/console.R`, `R/provider_anthropic.R`, `R/r_introspect_tools.R`.
- agenticr 0.3.3: `R/llm.R`, `R/tools.R`, `R/repl.R`.
- chattr 0.3.1: `R/backend-ellmer.R`, `R/chattr-package.R`, `R/ch-context.R`, `R/backend-openai.R`. gptstudio 0.4.0: `R/api_perform_request.R`, `R/service-openai_streaming.R`. mall 0.2.0: `R/m-backend-submit.R`, `R/m-vec-prompt.R`, `R/llm-verify.R`, `R/mall.R`. rollama 0.3.1: `R/chat.r`, `R/progress.R`, `R/lib.R`. openai 0.4.1: `R/create_chat_completion.R`.
- ravel 0.1.4: `R/providers_openai.R`. tidyprompt 0.4.0: `R/llm_providers.R`.

Installed packages (printed with `Rscript -e`): httr2 1.2.2 and 1.3.0 (`req_perform_connection`,
`retry_after`, `req_timeout`, `resp_stream_sse`, `stream_pull`, `stream_chunk_bytes`,
`resp_boundary_pushback`); ellmer 0.4.0 and 0.5.0.

gptr research reports: 02, 03, 04, 07, 08, 09, 10 (including its verification log), 12, 13, 15, 16, 18, 19, 21 in
`/Users/wanjun/Desktop/gptr/dev/research/`; spec `dev/spec/00-vision-brief.md`, `01-decision-register.md`.

No web pages were fetched for this report. External facts about provider APIs come from reports 07, 08 and 09,
as cited.

---

## 18. Claim ledger (self-check of the load-bearing claims)

| # | Claim | Label | How established |
|---|---|---|---|
| 1 | 37 tarballs match two CRAN db snapshots | VERIFIED | E0 output |
| 2 | ellmer's sync stream path uses a blocking `req_perform_connection()` | VERIFIED | `httr2.R:58`; printed `httr2::req_perform_connection` defaults |
| 3 | httr2 1.3.0 reads 65,536 bytes per blocking pull; 1.2.2 reads 1,024 | VERIFIED | printed `stream_chunk_bytes`, `stream_pull`, `resp_boundary_pushback` |
| 4 | Sync deltas arrive at end of stream (1.3.0) or in bursts (1.2.2); async and curl multi are incremental | VERIFIED (mock) / LIKELY (real providers) | E1, E2 |
| 5 | ellmer 0.5.0 takes 14–18 s for 2,000 deltas vs 1.35 s for 0.4.0 (re-run: 11.8 s vs 0.83 s) | VERIFIED | E14 (saved logs `e2e_*.out` hold one 0.4.0 run, so the earlier "1.35–1.50 s" range is not backed by a saved log); re-run V-5 |
| 6 | The cause is the S7 list validator on every partial-turn update | LIKELY | source (`chat.R:1403-1409`, `utils-S7.R:119-131`) plus micro-benchmark; httr2 alone 0.39 s |
| 7 | Interrupts escape ellmer; the partial is empty or dropped; "[empty string]" is replayed; the tool state is misreported | VERIFIED | E3 outputs plus wire log |
| 8 | Interrupt latency 1.2–1.4 s on 0.5.0/httr2 1.3.0 | VERIFIED (measured) / UNCERTAIN (cause) | E3 timestamps |
| 9 | ellmer's timeout is total | VERIFIED | E4; printed `req_timeout` |
| 10 | Mid-stream overload is not retried; Retry-After is uncapped | VERIFIED | E5; printed `retry_after`; `provider-claude.R:425-431` |
| 11 | `redacted_thinking` aborts ellmer | VERIFIED | E6 (0.4.0 and 0.5.0) |
| 12 | A 401 in stream mode leaves an empty "interrupted" partial turn | VERIFIED | E7 |
| 13 | Cross-provider replay emits invalid items | VERIFIED | E12 serialised output (internal `chat_body` used for measurement) |
| 14 | No argument validation (`NA` for a missing required argument) | VERIFIED | E9 |
| 15 | A truncated tool call aborts with a JSON parse error | VERIFIED | E10 |
| 16 | Tools run sequentially in `$chat()`; the steering hack gives an invalid order | VERIFIED (wire) / LIKELY (API rejection) | E11; report 07 §2.5 |
| 17 | Global token accounting; shallow clone shares callbacks | VERIFIED | E13 |
| 18 | tidyllm drops tool rounds from history and throws on tool errors | VERIFIED | `chat_pipeline.R:141-188`; `api_chat_completions.R:171-221` |
| 19 | tidyllm's idle deadline cannot fire under blocking reads | LIKELY | the file's own comment plus E2 mechanism |
| 20 | btw evaluates in the global environment with no timeout; sub-agents are synchronous | VERIFIED | `tool-run.R:123, 232-238`; grep; `tool-agent-subagent.R:480` |
| 21 | corteza writes handles into `globalenv()` | VERIFIED | `handles.R:135-160` |
| 22 | aisdk ids use `stats::runif()`; its log lives in `getwd()/.aisdk` | VERIFIED | `session_event_store.R:23-58, 141` |
| 23 | agenticr's decoder aborts the stream on split UTF-8 (the callback throws "invalid multibyte string") | LIKELY | E15 plus V-12 (agenticr's callback body run in isolation); agenticr not run end to end |
| 24 | llm.api never sets `is_error` | VERIFIED | grep plus `agent.R:640-670` |
| 25 | No package has a steering feature | VERIFIED | case-insensitive grep over 13 packages' `R/`; the only match is an unrelated comment (`mcptools/R/session.R:182`) |
| 26 | btw's full tool schema is 46,235 characters | VERIFIED | E16 re-run |
| 27 | aisdk streams Anthropic thinking text but never captures signatures or redacted thinking | VERIFIED (source, grep) / UNCERTAIN (effect) | `sse_aggregator.R:515-539`; package-wide grep for `signature_delta`/`redacted_thinking` |

---

## Appendix A. Scripts (house style: `=` for assignment, `|>` pipes; `<<-` only where a closure must update an outer variable)

### A.1 `mock_anthropic.R` — scenario-driven base-R mock of the Anthropic Messages API

```r
# mock_anthropic.R -- base-R mock of the Anthropic Messages API for track 10a experiments.
# Sequential (one connection at a time), SSE or JSON depending on body$stream.
# Request path selects the scenario: POST /<scenario>/v1/messages
# Every request body is appended to <logdir>/requests.jsonl (wire inspection).
# Inspired by track 15's mock_sse_base.R (serverSocket-based streaming).
# Usage: Rscript --vanilla mock_anthropic.R <port> <logdir>   (MOCK_CHUNKED=1 for chunked bodies)

args = commandArgs(trailingOnly = TRUE)
port = as.integer(args[1]); logdir = args[2]
dir.create(logdir, showWarnings = FALSE, recursive = TRUE)
`%||%` = function(a, b) if (is.null(a)) b else a
json = function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
sse = function(event, data) paste0("event: ", event, "\ndata: ", json(data), "\n\n")
counts = new.env()

read_request = function(con) {
  buf = raw(0)
  repeat {
    b = readBin(con, "raw", 1L)
    if (!length(b)) break
    buf = c(buf, b)
    n = length(buf)
    if (n >= 4 && identical(buf[(n - 3):n], charToRaw("\r\n\r\n"))) break
  }
  head = strsplit(rawToChar(buf), "\r\n", fixed = TRUE)[[1]]
  rl = strsplit(head[1], " ", fixed = TRUE)[[1]]
  hdr = tolower(sub(":.*$", "", head[-1])); val = trimws(sub("^[^:]*:", "", head[-1]))
  clen = as.integer(val[hdr == "content-length"][1] %||% 0L); if (is.na(clen)) clen = 0L
  body = raw(0)
  while (length(body) < clen) body = c(body, readBin(con, "raw", clen - length(body)))
  list(method = rl[1], path = rl[2], body = rawToChar(body))
}

msg_start = function(model) list(type = "message_start", message = list(id = "msg_mock", type = "message",
  role = "assistant", model = model, content = list(), stop_reason = NULL,
  usage = list(input_tokens = 100L, output_tokens = 1L, cache_read_input_tokens = 0L,
               cache_creation_input_tokens = 0L)))
text_block = function(index, pieces) {
  c(list(list("content_block_start", list(type = "content_block_start", index = index,
       content_block = list(type = "text", text = "")))),
    lapply(pieces, function(p) list("content_block_delta", list(type = "content_block_delta",
       index = index, delta = list(type = "text_delta", text = p)))),
    list(list("content_block_stop", list(type = "content_block_stop", index = index))))
}
tool_block = function(index, id, name, input) {
  js = json(input)
  cuts = unique(c(0L, floor(nchar(js) / 2), nchar(js)))
  c(list(list("content_block_start", list(type = "content_block_start", index = index,
       content_block = list(type = "tool_use", id = id, name = name,
                            input = structure(list(), names = character()))))),
    lapply(seq_len(length(cuts) - 1L), function(k) list("content_block_delta",
       list(type = "content_block_delta", index = index, delta = list(type = "input_json_delta",
            partial_json = substr(js, cuts[k] + 1L, cuts[k + 1L]))))),
    list(list("content_block_stop", list(type = "content_block_stop", index = index))))
}
finish = function(reason, out = 20L) list(
  list("message_delta", list(type = "message_delta", delta = list(stop_reason = reason),
       usage = list(output_tokens = out))),
  list("message_stop", list(type = "message_stop")))

plan = function(scenario, body) {
  msgs = body$messages; last = msgs[[length(msgs)]]
  after_tool = is.list(last$content) && length(last$content) > 0 &&
    any(vapply(last$content, function(b) identical(b$type, "tool_result"), TRUE))
  model = body$model %||% "mock"
  k = (counts[[scenario]] %||% 0L) + 1L; assign(scenario, k, envir = counts)
  ok = function(events, delay = 0.05, first = 0) list(status = 200L, events = events, delay = delay, first = first)
  if (grepl("^many[0-9]+$", scenario)) {
    n = as.integer(sub("many", "", scenario))
    return(ok(c(list(list("message_start", msg_start(model))), text_block(0L, rep("tok ", n)), finish("end_turn")), delay = 0))
  }
  switch(scenario,
    quick = ok(c(list(list("message_start", msg_start(model))), text_block(0L, "hello"), finish("end_turn"))),
    slow = ok(c(list(list("message_start", msg_start(model))),
                text_block(0L, sprintf("tok%02d ", 1:12)), finish("end_turn")), delay = 0.25),
    long = ok(c(list(list("message_start", msg_start(model))),
                text_block(0L, sprintf("tok%02d ", 1:16)), finish("end_turn")), delay = 0.25),
    ttft = ok(c(list(list("message_start", msg_start(model))),
                text_block(0L, sprintf("tok%02d ", 1:4)), finish("end_turn")), delay = 0.05, first = 3),
    overload = list(status = 200L, delay = 0.1, first = 0, events = c(
                list(list("message_start", msg_start(model))),
                text_block(0L, c("partial ", "answer ", "then "))[1:3],
                list(list("error", list(type = "error", error = list(type = "overloaded_error",
                     message = "Overloaded")))))),
    redacted = ok(c(list(list("message_start", msg_start(model))),
                list(list("content_block_start", list(type = "content_block_start", index = 0L,
                     content_block = list(type = "redacted_thinking", data = "RVhBTVBMRS1FTkNSWVBURUQ="))),
                     list("content_block_stop", list(type = "content_block_stop", index = 0L))),
                text_block(1L, c("visible ", "answer")), finish("end_turn"))),
    thinking = ok(c(list(list("message_start", msg_start(model)),
                list("content_block_start", list(type = "content_block_start", index = 0L,
                     content_block = list(type = "thinking", thinking = "", signature = ""))),
                list("content_block_delta", list(type = "content_block_delta", index = 0L,
                     delta = list(type = "thinking_delta", thinking = "Let me think. ")))),
                list(list("content_block_delta", list(type = "content_block_delta", index = 0L,
                     delta = list(type = "signature_delta", signature = "SIG-abc123==")))),
                list(list("content_block_stop", list(type = "content_block_stop", index = 0L))),
                text_block(1L, c("The answer ", "is 42.")), finish("end_turn"))),
    r429 = if (k == 1L) list(status = 429L, retry_after = "2",
                body = json(list(type = "error", error = list(type = "rate_limit_error", message = "slow down"))))
           else ok(c(list(list("message_start", msg_start(model))), text_block(0L, "after-retry"), finish("end_turn"))),
    e401 = list(status = 401L, body = json(list(type = "error",
                error = list(type = "authentication_error", message = "invalid x-api-key")))),
    tool = if (after_tool) ok(c(list(list("message_start", msg_start(model))),
                text_block(0L, "done after tool"), finish("end_turn")))
           else ok(c(list(list("message_start", msg_start(model))), text_block(0L, "calling tool "),
                tool_block(1L, "toolu_01", "slow_tool", list(secs = 4)), finish("tool_use"))),
    trunc = ok(c(list(list("message_start", msg_start(model))), text_block(0L, "writing code "),
                list(list("content_block_start", list(type = "content_block_start", index = 1L,
                     content_block = list(type = "tool_use", id = "toolu_T", name = "stamp", input = structure(list(), names = character())))),
                     list("content_block_delta", list(type = "content_block_delta", index = 1L,
                     delta = list(type = "input_json_delta", partial_json = "{\"label\": \"unfinished")))),
                finish("max_tokens"))),
    par = if (after_tool) ok(c(list(list("message_start", msg_start(model))),
                text_block(0L, "both done"), finish("end_turn")))
          else ok(c(list(list("message_start", msg_start(model))),
                tool_block(0L, "toolu_A", "stamp", list(label = "A")),
                tool_block(1L, "toolu_B", "stamp", list(label = "B")), finish("tool_use"))),
    list(status = 404L, body = json(list(type = "error", error = list(type = "not_found_error", message = scenario))))
  )
}

as_message = function(events) {
  # Assemble the non-streaming JSON message from the same event plan.
  msg = NULL; content = list()
  for (e in events) {
    d = e[[2]]
    if (d$type == "message_start") msg = d$message
    if (d$type == "content_block_start") content[[d$index + 1L]] = d$content_block
    if (d$type == "content_block_delta") {
      i = d$index + 1L
      if (d$delta$type == "text_delta") content[[i]]$text = paste0(content[[i]]$text, d$delta$text)
      if (d$delta$type == "thinking_delta") content[[i]]$thinking = paste0(content[[i]]$thinking, d$delta$thinking)
      if (d$delta$type == "signature_delta") content[[i]]$signature = d$delta$signature
      if (d$delta$type == "input_json_delta") content[[i]]$partial = paste0(content[[i]]$partial %||% "", d$delta$partial_json)
    }
    if (d$type == "message_delta") { msg$stop_reason = d$delta$stop_reason; msg$usage$output_tokens = d$usage$output_tokens }
  }
  content = lapply(content, function(b) { if (!is.null(b$partial)) { b$input = jsonlite::fromJSON(b$partial, simplifyVector = FALSE); b$partial = NULL }; b })
  msg$content = content
  msg
}

chunked = identical(Sys.getenv("MOCK_CHUNKED"), "1")
frame = function(s) if (chunked) paste0(sprintf("%x", nchar(s, "bytes")), "\r\n", s, "\r\n") else s
srv = serverSocket(port)
cat("LISTENING\n"); flush(stdout())
repeat {
  con = socketAccept(srv, blocking = TRUE, open = "r+b", timeout = 600)
  req = read_request(con)
  scenario = strsplit(req$path, "/", fixed = TRUE)[[1]][2]
  body = tryCatch(jsonlite::fromJSON(req$body, simplifyVector = FALSE), error = function(e) list())
  cat(json(list(t = format(Sys.time(), "%H:%M:%OS3"), scenario = scenario, path = req$path, body = body)), "\n",
      file = file.path(logdir, "requests.jsonl"), append = TRUE, sep = "")
  p = plan(scenario, body)
  res = tryCatch({
    if (!identical(p$status, 200L)) {
      extra = if (!is.null(p$retry_after)) paste0("retry-after: ", p$retry_after, "\r\n") else ""
      writeBin(charToRaw(paste0("HTTP/1.1 ", p$status, " Err\r\nContent-Type: application/json\r\n", extra,
        "Content-Length: ", nchar(p$body, "bytes"), "\r\nConnection: close\r\n\r\n", p$body)), con)
    } else if (isFALSE(body$stream)) {
      Sys.sleep(p$first)
      out = json(as_message(p$events))
      writeBin(charToRaw(paste0("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ",
        nchar(out, "bytes"), "\r\nConnection: close\r\n\r\n", out)), con)
    } else {
      Sys.sleep(p$first)
      writeBin(charToRaw(paste0("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n",
        if (chunked) "Transfer-Encoding: chunked\r\n" else "", "Connection: close\r\n\r\n")), con)
      flush(con)
      for (e in p$events) {
        writeBin(charToRaw(frame(sse(e[[1]], e[[2]]))), con); flush(con)
        Sys.sleep(p$delay)
      }
      if (chunked) { writeBin(charToRaw("0\r\n\r\n"), con); flush(con) }
    }
    "ok"
  }, error = function(e) paste("client went away:", conditionMessage(e)))
  cat(format(Sys.time(), "%H:%M:%OS3"), scenario, res, "\n", file = file.path(logdir, "server.log"), append = TRUE)
  try(close(con), silent = TRUE)
}
```

### A.2 `child_ellmer.R` — one ellmer scenario per process (E3–E13)

```r
# child_ellmer.R -- runs one ellmer scenario against mock_anthropic.R; the driver may SIGINT it.
# Usage: Rscript --vanilla child_ellmer.R <port> <case>
args = commandArgs(trailingOnly = TRUE)
port = args[1]; case = args[2]
suppressPackageStartupMessages(library(ellmer))
cat("ELLMER", as.character(packageVersion("ellmer")), "HTTR2", as.character(packageVersion("httr2")), "\n")
base = function(s) sprintf("http://127.0.0.1:%s/%s/v1", port, s)
mk = function(s, ...) chat_anthropic(base_url = base(s), credentials = function() "test-key",
                                     model = "claude-mock-1", echo = "none", ...)
t0 = Sys.time()
el = function() sprintf("%.2fs", as.numeric(difftime(Sys.time(), t0, units = "secs")))
outcome = function(expr) tryCatch({ force(expr); "completed" },
  interrupt = function(c) "INTERRUPT condition reached top level",
  error = function(e) paste0("ERROR <", paste(class(e), collapse = "/"), "> ", gsub("\n", " | ", conditionMessage(e))))
show_turns = function(chat) {
  tt = chat$get_turns()
  cat("TURNS n =", length(tt), "\n")
  for (i in seq_along(tt)) {
    t = tt[[i]]
    cls = class(t)[1]
    kinds = paste(vapply(t@contents, function(x) class(x)[1], ""), collapse = ",")
    extra = if (inherits(t, "ellmer::AssistantPartialTurn") || grepl("Partial", cls)) paste0(" reason=", t@reason) else ""
    tok = if (grepl("Assistant", cls)) paste0(" tokens=", paste(t@tokens, collapse = "/")) else ""
    cat(sprintf("  [%d] %s contents={%s} text=%s%s%s\n", i, cls, kinds, encodeString(substr(t@text, 1, 60), quote = '"'), extra, tok))
  }
}
cat("READY\n"); flush(stdout())

if (case == "slow_int") {
  ch = mk("slow")
  cat("OUTCOME", outcome(ch$chat("hi", echo = "output")), el(), "\n")
  show_turns(ch)
  ch2res = outcome(ch$chat("second question", echo = "none"))
  cat("SECOND", ch2res, "\n"); show_turns(ch)
}
if (case == "slow_int_noecho") {
  ch = mk("slow")
  cat("OUTCOME", outcome(ch$chat("hi", echo = "none")), el(), "\n")
  show_turns(ch)
}
if (case == "ttft_int") {
  ch = mk("ttft")
  cat("OUTCOME", outcome(ch$chat("hi", echo = "output")), el(), "\n")
  show_turns(ch)
}
if (case == "timeout") {
  options(ellmer_timeout_s = 1.5)
  ch = mk("long")
  cat("OUTCOME", outcome(ch$chat("hi", echo = "output")), el(), "\n")
  show_turns(ch)
}
if (case == "overload") {
  ch = mk("overload")
  cat("OUTCOME", outcome(ch$chat("hi", echo = "output")), el(), "\n")
  show_turns(ch)
}
if (case == "redacted_stream") {
  ch = mk("redacted")
  cat("OUTCOME", outcome(ch$chat("hi", echo = "output")), el(), "\n")
  show_turns(ch)
}
if (case == "redacted_value") {
  ch = mk("redacted")
  cat("OUTCOME", outcome(ch$chat("hi", echo = "none")), el(), "\n")
  show_turns(ch)
}
if (case == "r429") {
  ch = mk("r429")
  cat("OUTCOME", outcome(print(ch$chat("hi", echo = "none"))), el(), "\n")
}
if (case == "e401_stream") {
  ch = mk("e401")
  cat("OUTCOME", outcome(ch$chat("hi", echo = "output")), el(), "\n")
  show_turns(ch)
}
if (case == "e401_value") {
  ch = mk("e401")
  cat("OUTCOME", outcome(ch$chat("hi", echo = "none")), el(), "\n")
  show_turns(ch)
}
if (case == "tool_int") {
  ch = mk("tool")
  slow_tool = function(secs) { cat("TOOL start", el(), "\n"); Sys.sleep(secs); cat("TOOL end", el(), "\n"); "slept" }
  ch$register_tool(tool(slow_tool, "Sleep", arguments = list(secs = type_number())))
  cat("OUTCOME", outcome(ch$chat("hi", echo = "output")), el(), "\n")
  show_turns(ch)
  cat("SECOND", outcome(ch$chat("continue please", echo = "none")), "\n")
  show_turns(ch)
}
if (case == "par") {
  ch = mk("par")
  stamp = function(label) { s = el(); Sys.sleep(0.5); paste(label, s, el()) }
  ch$register_tool(tool(stamp, "Stamp", arguments = list(label = type_string())))
  cat("OUTCOME", outcome(ch$chat("hi", echo = "none")), el(), "\n")
  res = ch$get_turns()[[3]]@contents
  for (r in res) cat("  RESULT", r@request@id, r@value, "\n")
}
if (case == "steer_hack") {
  ch = mk("tool")
  slow_tool = function(secs) "slept"
  ch$register_tool(tool(slow_tool, "Sleep", arguments = list(secs = type_number())))
  n = 0
  ch$on_request_start(function(turns) {
    n <<- n + 1
    if (n == 2) ch$set_turns(c(ch$get_turns(), list(UserTurn("STEER: use TPM instead"))))
  })
  cat("OUTCOME", outcome(ch$chat("hi", echo = "none")), el(), "\n")
  show_turns(ch)
}
if (case == "tokens_global") {
  a = mk("quick"); b = mk("quick")
  invisible(a$chat("one", echo = "none")); invisible(b$chat("two", echo = "none"))
  cat("A cost/tokens:\n"); print(a$get_tokens())
  cat("token_usage():\n"); print(token_usage())
}
if (case == "clone") {
  a = mk("quick")
  invisible(a$chat("one", echo = "none"))
  b = a$clone()
  invisible(b$chat("two", echo = "none"))
  cat("turns a =", length(a$get_turns()), " turns b =", length(b$get_turns()), "\n")
  pa = a$.__enclos_env__$private; pb = b$.__enclos_env__$private
  cat("shallow clone shares the on_tool_request CallbackManager:", identical(pa$callback_on_tool_request, pb$callback_on_tool_request), "\n")
  d = a$clone(deep = TRUE); pd = d$.__enclos_env__$private
  cat("deep clone shares it:", identical(pa$callback_on_tool_request, pd$callback_on_tool_request), "\n")
}
if (case == "handoff") {
  ch = mk("thinking", params = params(reasoning_tokens = 2048))
  invisible(ch$chat("hi", echo = "none"))
  show_turns(ch)
  th = ch$get_turns()[[2]]@contents[[1]]
  cat("anthropic thinking extra:", jsonlite::toJSON(th@extra, auto_unbox = TRUE), "\n")
  oa = chat_openai(credentials = function() "k", model = "gpt-5-mock", echo = "none")
  cb_body = function(chat, turns) if ("model" %in% names(formals(ellmer:::chat_body))) ellmer:::chat_body(chat$get_provider(), chat$get_model_object(), stream = FALSE, turns = turns) else ellmer:::chat_body(chat$get_provider(), stream = FALSE, turns = turns)
  body = cb_body(oa, ch$get_turns(include_system_prompt = TRUE))
  cat("OpenAI /responses input built from the Anthropic turns:\n", jsonlite::toJSON(body$input, auto_unbox = TRUE, pretty = FALSE), "\n")
  # And the reverse: an OpenAI reasoning item replayed to Anthropic
  item = list(type = "reasoning", id = "rs_1", summary = list(list(type = "summary_text", text = "I reasoned.")), encrypted_content = "ENC-OPAQUE")
  oa_turn = AssistantTurn(contents = list(ContentThinking(thinking = "I reasoned.", extra = item), ContentText("Answer from GPT.")))
  turns2 = list(UserTurn("q"), oa_turn, UserTurn("follow-up"))
  an = mk("quick")
  body2 = cb_body(an, turns2)
  cat("Anthropic messages built from an OpenAI turn:\n", jsonlite::toJSON(body2$messages, auto_unbox = TRUE), "\n")
}
cat("END", el(), "\n")
if (case == "trunc") {
  ch = mk("trunc")
  stamp = function(label) { cat("TOOL RAN with", label, "\n"); "stamped" }
  ch$register_tool(tool(stamp, "Stamp", arguments = list(label = type_string())))
  cat("OUTCOME", outcome(withCallingHandlers(ch$chat("hi", echo = "output"),
      warning = function(w) { cat("WARNING:", conditionMessage(w), "\n"); invokeRestart("muffleWarning") })), el(), "\n")
  show_turns(ch)
}
```

### A.3 `driver_ellmer.R`

Usage: `Rscript --vanilla driver_ellmer.R <tag> <rlib-or-""> <port> case[@interrupt_s] ...`.
Examples: `e050 $T10R 28731 slow_int@1.2 ttft_int@1.0 timeout overload`; `e040 "" 28801 …`.

```r
library(processx)
args = commandArgs(trailingOnly = TRUE)
tag = args[1]; rlib = if (length(args) >= 2 && nzchar(args[2])) args[2] else ""; port = args[3]
here = getwd(); logdir = file.path(here, paste0("log_", tag))
unlink(logdir, recursive = TRUE)
srv = process$new("/usr/local/bin/Rscript", c("--vanilla", "mock_anthropic.R", port, logdir), stdout = "|", stderr = "|")
repeat { srv$poll_io(5000); if (any(grepl("LISTENING", srv$read_output_lines())) || !srv$is_alive()) break }
env = c("current", R_LIBS = rlib)
run_case = function(case, interrupt_after = NA, timeout = 60000) {
  p = process$new("/usr/local/bin/Rscript", c("--vanilla", "child_ellmer.R", port, case), stdout = "|", stderr = "2>&1", env = env)
  out = character()
  repeat { p$poll_io(10000); out = c(out, p$read_output_lines()); if (any(grepl("READY", out)) || !p$is_alive()) break }
  t0 = Sys.time()
  if (!is.na(interrupt_after)) { Sys.sleep(interrupt_after); p$interrupt(); cat(sprintf("[driver] SIGINT sent %.2fs after READY\n", as.numeric(difftime(Sys.time(), t0, units = "secs")))) }
  p$wait(timeout)
  if (p$is_alive()) { p$kill(); out = c(out, "[driver] KILLED after timeout") }
  out = c(out, p$read_all_output_lines())
  cat(sprintf("===== %s | case=%s | exit=%s | wall=%.2fs\n", tag, case, p$get_exit_status(), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  cat(paste0("  | ", out), sep = "\n")
}
cases = commandArgs(trailingOnly = TRUE)[-(1:3)]
for (cs in cases) {
  parts = strsplit(cs, "@", fixed = TRUE)[[1]]
  run_case(parts[1], if (length(parts) > 1) as.numeric(parts[2]) else NA)
}
srv$kill()
cat("----- server.log\n"); cat(readLines(file.path(logdir, "server.log")), sep = "\n")
```

### A.4 `stream_timing.R` (E1)

Run by `run_timing.sh <port> <chunked 0|1> <rlib>`. That script starts the mock with `MOCK_CHUNKED`, sleeps 1.5 s,
then runs this script with `R_LIBS=<rlib>`.

```r
args = commandArgs(trailingOnly = TRUE); port = args[1]; scen = args[2]
suppressPackageStartupMessages(library(ellmer))
cat("ELLMER", as.character(packageVersion("ellmer")), "HTTR2", as.character(packageVersion("httr2")),
    "CURL", as.character(packageVersion("curl")), "chunked =", Sys.getenv("MOCK_CHUNKED"), "\n")
url = sprintf("http://127.0.0.1:%s/%s/v1", port, scen)
# (a) ellmer sync stream (warm-up call first so first-use costs are excluded)
warm = chat_anthropic(base_url = sprintf("http://127.0.0.1:%s/quick/v1", port), credentials = function() "k", model = "claude-mock-1", echo = "none")
coro::loop(for (x in warm$stream("warm")) NULL)
ch = chat_anthropic(base_url = url, credentials = function() "k", model = "claude-mock-1", echo = "none")
t0 = Sys.time(); arr = numeric()
coro::loop(for (x in ch$stream("hi")) arr = c(arr, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
cat("ellmer $stream(): n =", length(arr), " arrival s =", paste(sprintf("%.2f", arr), collapse = " "), "\n")
# (b) ellmer async stream driven by later
ch2 = chat_anthropic(base_url = url, credentials = function() "k", model = "claude-mock-1", echo = "none")
t0 = Sys.time(); arr2 = numeric(); done = FALSE
gen = ch2$stream_async("hi")
p = coro::async(function() { for (x in coro::await_each(gen)) arr2 <<- c(arr2, as.numeric(difftime(Sys.time(), t0, units = "secs"))); done <<- TRUE })()
while (!done) later::run_now(0.05)
cat("ellmer $stream_async(): n =", length(arr2), " arrival s =", paste(sprintf("%.2f", arr2), collapse = " "), "\n")
# (c) curl multi + poll loop (the track-02/15 design), raw bytes per callback
body = jsonlite::toJSON(list(model = "m", max_tokens = 10, stream = TRUE,
  messages = list(list(role = "user", content = "hi"))), auto_unbox = TRUE)
h = curl::new_handle(url = paste0(url, "/messages"), post = TRUE, postfields = body, pipewait = 0L)
curl::handle_setheaders(h, "content-type" = "application/json")
pool = curl::new_pool(); arr3 = numeric(); fin = FALSE; t0 = Sys.time()
curl::multi_add(h, pool = pool, data = function(x, final) {
  n_ev = length(gregexpr("\n\n", rawToChar(x), fixed = TRUE)[[1]])
  arr3 <<- c(arr3, rep(as.numeric(difftime(Sys.time(), t0, units = "secs")), n_ev))
}, done = function(r) fin <<- TRUE, fail = function(m) { fin <<- TRUE; cat("fail", m, "\n") })
while (!fin) curl::multi_run(timeout = 0.05, poll = TRUE, pool = pool)
cat("curl multi: SSE events =", length(arr3), " arrival s =", paste(sprintf("%.2f", arr3), collapse = " "), "\n")
```

### A.5 `httr2_timing.R` (E2) and `httr2_many.R` (E14, httr2 alone)

```r
# httr2_timing.R <port>
args = commandArgs(trailingOnly = TRUE); port = args[1]
cat("HTTR2", as.character(packageVersion("httr2")), "CURL", as.character(packageVersion("curl")), "\n")
body = list(model = "m", max_tokens = 10, stream = TRUE, messages = list(list(role = "user", content = "hi")))
req = httr2::request(sprintf("http://127.0.0.1:%s/slow/v1/messages", port)) |> httr2::req_body_json(body)
for (blocking in c(TRUE, FALSE)) {
  t0 = Sys.time(); arr = numeric()
  resp = httr2::req_perform_connection(req, blocking = blocking)
  repeat {
    ev = httr2::resp_stream_sse(resp)
    if (is.null(ev)) { if (httr2::resp_stream_is_complete(resp)) break; next }
    arr = c(arr, as.numeric(difftime(Sys.time(), t0, units = "secs")))
  }
  close(resp)
  cat(sprintf("blocking=%s: events=%d arrival s = %s\n", blocking, length(arr), paste(sprintf("%.2f", arr), collapse = " ")))
}

# httr2_many.R <port>
args = commandArgs(trailingOnly = TRUE); port = args[1]
cat("HTTR2", as.character(packageVersion("httr2")), "\n")
body = list(model = "m", max_tokens = 10, stream = TRUE, messages = list(list(role = "user", content = "hi")))
for (n in c(1000L, 2000L)) {
  req = httr2::request(sprintf("http://127.0.0.1:%s/many%d/v1/messages", port, n)) |> httr2::req_body_json(body)
  k = 0L
  t = system.time({
    resp = httr2::req_perform_connection(req)
    repeat { ev = httr2::resp_stream_sse(resp); if (is.null(ev)) break; k = k + 1L; d = jsonlite::parse_json(ev$data) }
    close(resp)
  })[["elapsed"]]
  cat(sprintf("n=%d: httr2 resp_stream_sse + parse_json: %d events in %.2fs\n", n, k, t))
}
```

### A.6 `e2e_accum.R` and `accum_bench.R` (E14)

```r
# e2e_accum.R <port> <n1> <n2> ...   (run_e2e.sh passes 250 500 1000 2000)
args = commandArgs(trailingOnly = TRUE); port = args[1]
suppressPackageStartupMessages(library(ellmer))
cat("ELLMER", as.character(packageVersion("ellmer")), "HTTR2", as.character(packageVersion("httr2")), "\n")
for (n in as.integer(args[-1])) {
  url = sprintf("http://127.0.0.1:%s/many%d/v1", port, n)
  ch = chat_anthropic(base_url = url, credentials = function() "k", model = "claude-mock-1", echo = "none")
  k = 0L
  t_e = system.time(coro::loop(for (x in ch$stream("hi")) k = k + 1L))[["elapsed"]]
  body = jsonlite::toJSON(list(model = "m", max_tokens = 10, stream = TRUE, messages = list(list(role = "user", content = "hi"))), auto_unbox = TRUE)
  h = curl::new_handle(url = paste0(url, "/messages"), post = TRUE, postfields = body)
  curl::handle_setheaders(h, "content-type" = "application/json")
  t_c = system.time({ r = curl::curl_fetch_memory(paste0(url, "/messages"), handle = h) })[["elapsed"]]
  cat(sprintf("n=%5d deltas: ellmer $stream() consumed %d chunks in %6.2fs | raw curl fetch of same stream %5.2fs (%d bytes)\n",
              n, k, t_e, t_c, length(r$content)))
}

# accum_bench.R -- the per-delta pattern of TurnAccumulator$update_turn vs alternatives
suppressPackageStartupMessages(library(ellmer))
for (n in c(2000, 5000, 10000)) {    # the 10000 case was stopped after > 5 minutes
  turn = AssistantPartialTurn()
  t1 = system.time(for (i in seq_len(n)) turn@contents = c(turn@contents, list(ContentText("tok "))))[["elapsed"]]
  s = ""
  t2 = system.time(for (i in seq_len(n)) s = paste0(s, "tok "))[["elapsed"]]
  parts = vector("list", n)
  t3 = system.time({ for (i in seq_len(n)) parts[[i]] = "tok "; out = paste(unlist(parts), collapse = "") })[["elapsed"]]
  cat(sprintf("n=%5d  S7 contents append: %6.2fs  paste0 accumulate: %5.3fs  preallocated list + one paste: %5.3fs\n", n, t1, t2, t3))
}
# output (ellmer 0.5.0):
# n= 2000  S7 contents append:   8.51s  paste0 accumulate: 0.011s  preallocated list + one paste: 0.000s
# n= 5000  S7 contents append: 139.19s  paste0 accumulate: 0.223s  preallocated list + one paste: 0.002s
```

### A.7 `tool_validation.R` (E9)

```r
suppressPackageStartupMessages(library(ellmer))
cat("ELLMER", as.character(packageVersion("ellmer")), "\n")
`%||%` = function(a, b) if (is.null(a)) b else a
f = function(code, n) paste0("code=", format(code), " (", class(code)[1], ") n=", format(n), " (", class(n)[1], ")")
td = tool(f, "t", arguments = list(code = type_string("R code"), n = type_integer("rows")))
show = function(args) {
  req = ContentToolRequest(id = "c1", name = "f", arguments = args, tool = td)
  res = ellmer:::invoke_tool(req)   # internal, used for measurement only
  cat(sprintf("%-40s -> value=%s | error=%s\n", as.character(jsonlite::toJSON(args, auto_unbox = TRUE)),
      format(res@value %||% "NULL"), if (is.null(res@error)) "NULL" else conditionMessage(res@error)))
}
show(list(code = "1+1", n = 3L))
show(list(n = 3L))                       # required 'code' missing
show(list(code = "1+1", n = "three"))    # wrong type
show(list(code = list(1, 2), n = 3L))    # array where string expected
show(list(code = "1+1", n = 3L, extra = TRUE))
```

### A.8 E15 (UTF-8 split) and E0 (MD5)

```r
# LANG=en_US.UTF-8 Rscript --vanilla -e '...'
x = charToRaw("data: {\"t\":\"中文\"}\n\n")
cut = which(x == as.raw(0xe4))[1] + 1   # split inside the 3-byte character
a = rawToChar(x[1:cut]); b = rawToChar(x[(cut + 1):length(x)])
r1 = tryCatch(strsplit(a, "\n")[[1]], error = function(e) paste("ERROR:", conditionMessage(e)))  # NA + warnings
r2 = tryCatch(trimws(a), error = function(e) paste("ERROR:", conditionMessage(e)))               # "input string 1 is invalid UTF-8"
joined = paste0(a, b); validUTF8(joined)                                                         # TRUE

# md5check.R: compares tools::md5sum() of each track10/src/*.tar.gz with the MD5sum column of
# track10/cran_db2.rds and verify-10/cran_db_v10.rds; prints one row per tarball and "all ok: TRUE".
```

---

## Verification log

An adversarial fact-check pass was run on 2026-09-29, after the report was written. It re-read the cited
source in `$S` (the same MD5-verified CRAN extractions), printed installed functions, and re-ran
experiments with `Rscript --vanilla` against the report's own mock. The runs used ellmer 0.5.0/httr2 1.3.0
from `$T10R` and ellmer 0.4.0/httr2 1.2.2 from the system library. Scripts and outputs are in
`.../scratchpad/work/verify-10a/` (`httr2_timing.R`, `stream_timing.R`, `e2e_accum.R`,
`tool_validation.R`, `clone_check.R`, `cancel_async.R`, `e15_sim.R`). No API calls were made and nothing
was installed.

Verdicts:
- **CONFIRMED**: the claim stands as written.
- **CORRECTED**: the claim was wrong, and the text above has been fixed.
- **QUALIFIED**: the claim was true but overstated or incomplete, and it has been softened or completed.

| V | Claim (as originally written) | Verdict | Source / evidence |
|---|---|---|---|
| V-1 | Blocking httr2 reads deliver nothing until 64 KiB or stream end (1.3.0), and deliver in ~1 KB bursts (1.2.2); non-blocking reads are incremental (E2) | CONFIRMED | Re-run: 1.3.0 blocking, all 17 events at 4.41 s; non-blocking, 0.02…4.09 s. 1.2.2 blocking: bursts at 1.80 s and 4.08 s. Printed `httr2:::stream_chunk_bytes` = 65536 and `stream_pull` (1.3.0); `resp_boundary_pushback` reads `min(max_size + 1, 1024)` (1.2.2) |
| V-2 | ellmer's sync `$stream()` first delta arrives at the end of the stream; async and curl multi are incremental (E1) | CONFIRMED | Re-run: 0.5.0 `$stream()` first delta 4.39 s; 0.4.0 bursts 1.87 s / 4.14 s; `$stream_async()` from 0.70 s (so the 2.27 s async start in E1 was a one-off); curl multi 0.25 s. Sync path `httr2.R:58` uses a default (blocking) `req_perform_connection()` |
| V-3 | `$chat()` streams only when `echo != "none"`, and `echo` defaults to `"none"` in functions and scripts | CONFIRMED | `chat.R:395-413` (`stream = echo != "none"`); `utils.R:82-108` (`env_is_user_facing()` → "output", else "none") |
| V-4 | ellmer 0.5.0's "cost per delta is quadratic" | QUALIFIED (wording) | Total cost is quadratic: each append re-validates the whole list (`utils-S7.R:119-131`, `chat.R:1403-1409`). Micro-benchmark re-run: 0.15 / 0.54 / 2.26 / 9.05 s for 250 / 500 / 1,000 / 2,000 appends (~4× per doubling). End-to-end re-run at 2,000 deltas: 11.76 s (0.5.0) vs 0.83 s (0.4.0). The "1.35–1.50 s" range for 0.4.0 has only one saved run (1.35 s), and the text was adjusted |
| V-5 | Retry-After is uncapped; ellmer sets `max_tries = 3` and no `max_seconds` | CONFIRMED | Printed httr2 1.3.0 `retry_after()` (returns the header value), `req_perform_connection()` (sleeps `delay` unconditionally) and `retry_max_seconds()` (default `Inf`); `ellmer/R/httr2.R:119-128` |
| V-6 | ellmer's timeout is a total-transfer limit, 300 s by default | CONFIRMED | `httr2.R:120`; printed `httr2::req_timeout` sets `timeout_ms`; E4 log `run_e050_a.out` |
| V-7 | `stream_controller()` "cannot cancel during TTFT or during a stalled stream" | CONFIRMED, QUALIFIED | New run `cancel_async.R`. With `$stream_async()`, a cancel at 0.5 s ended a flowing stream at 0.65 s (async cancel works mid-body). During a 3 s TTFT, the `later` callback scheduled at 0.5 s ran at 3.35 s and the stream ended at 3.67 s: `req_perform_connection(blocking = FALSE)` blocks the session until the headers arrive. The stalled-body case in async mode was not tested |
| V-8 | ellmer's async path is non-blocking (implied by "incremental") | QUALIFIED (new finding) | Same run as V-7: the async path blocks the whole R event loop during the header wait. Added to §1 item 2, §3.1, §12 and §13 |
| V-9 | An interrupt replays "[empty string]"; after a tool ran, the next request says "Chat ended before the tool could be invoked." | CONFIRMED | Wire logs `log_e050/requests.jsonl` #2 and `log_e050c/requests.jsonl` #2; `chat.R:1279-1300`. Qualified: the empty partial occurred because the blocking read had not delivered the deltas to R. With delivered deltas (E5) the partial kept them |
| V-10 | `redacted_thinking` aborts ellmer (0.4.0 and 0.5.0); value mode loses the turn | CONFIRMED | `provider-claude.R:492-531` (no branch, `cli_abort(.internal = TRUE)` at `:527-530`); logs `run_e040.out`, `run_e050_b.out` |
| V-11 | A mid-stream `overloaded_error` is slept on, not retried | CONFIRMED | `provider-claude.R:424-432` (`Sys.sleep(backoff_default(1))`, `# TODO: track number of retries`); E5 logs |
| V-12 | agenticr "drops the event" on a UTF-8 character split across chunks | CORRECTED | `e15_sim.R` ran agenticr's callback body (`agenticr/R/llm.R:160-173`) in `en_US.UTF-8`. `strsplit()` warns, then `nchar(raw_text)` errors "invalid multibyte string, element 1". The callback throws, so the stream aborts, and the complete event earlier in the chunk is also lost |
| V-13 | No argument validation: missing required → `NA`, `"three"` passes as integer, array passes as string; only extra arguments are rejected (E9) | CONFIRMED | Re-run of `tool_validation.R`, identical on 0.4.0 and 0.5.0; `chat-tools.R:264-280` |
| V-14 | `on_tool_request` "can only deny: it cannot ask, modify the arguments, or apply a permission mode" | QUALIFIED | Deny is the only structured outcome, and the return value is ignored, so arguments cannot be modified (`chat-tools.R:50-62, 282-295`). But ellmer's own `tool_reject()` example asks the user with `utils::menu()` and keeps an "Always" allow-list (`tools-def.R:439-453`). Text changed to "no ask verdict; prompting is ad hoc in the callback" |
| V-15 | The loop has no round limit and runs tools sequentially in `$chat()` | CONFIRMED | `chat.R:781-839` (no counter; grep for `max_turns|max_rounds|max_tool|max_steps` in `ellmer/R/` finds 0); `chat-tools.R:31-78`; E11 logs |
| V-16 | "`AssistantTurn` records no provider, model or API" | QUALIFIED | No such field (`turns.R:129-150`). But `@json` keeps the raw response (`provider-claude.R:546-552`), which usually carries `model`. It is not used on replay |
| V-17 | Cross-provider replay emits `{"signature":…}` and `"signature":{}` and drops `encrypted_content` (E12) | CONFIRMED | `provider-openai.R:504-510` returns `x@extra`; `provider-claude.R:961-975` emits `x@extra$signature`; log `run_e050_b.out` (handoff) |
| V-18 | Tool results are strings; content results are "unrolled" into user content | CONFIRMED | `content.R:384-390`; `chat-tools.R:149-174` (`normalize_tool_result`); `chat-tools-content.R:1-75` (comment "Very few providers support anything other than text results"); `provider-claude.R:936-947`; `provider-openai.R:604-614` |
| V-19 | `$clone()` is shallow and shares the callback managers | CONFIRMED (strengthened) | `clone_check.R`: on 0.4.0 and 0.5.0, a callback registered on the clone fires when the original's manager is invoked; `clone(deep = TRUE)` separates them; `Chat` has no `deep_clone` method |
| V-20 | Global token accounting "rules out" concurrent agents | QUALIFIED | Mechanism confirmed (`tokens.R:23-58`). But `token_usage()` is a process-wide summary by design, and per-chat `$get_tokens()` is correct (E13: 100/20). Wording softened in §1 item 10, §3.5, §13, INFRA-15 and INFRA-20 |
| V-21 | `parallel_chat()` "cannot mix models or prompts per conversation" | CORRECTED | Each conversation gets its own prompt (`parallel-chat.R:89-94`). It cannot mix models, system prompts or prior histories |
| V-22 | ellmer: "Only `parallel_chat()` throttles … No rate-limit headers are read" | CORRECTED | The Mistral provider reads `ratelimitbysize-reset` and throttles to 1 request per second (`provider-mistral.R:90-98`). Anthropic, OpenAI and Google read none |
| V-23 | Provider generics are not exported | CONFIRMED | `ellmer/NAMESPACE` exports `Provider` and `Model` but none of `chat_request`, `chat_body`, `stream_parse`, `value_turn`, `as_json`, `base_request` |
| V-24 | tidyllm: bare `do.call()` aborts on tool error; orphaned call ids; history keeps only the final text; 10 rounds then `stop()`; "no approval, abort or steering" | CONFIRMED, QUALIFIED | `api_chat_completions.R:171-219`, `api_claude.R:237-278`, `api_gemini.R:278-320` and `api_openai.R:214-243` have no `tryCatch`, but `api_ollama.R:181-190` catches. `tools.R:341-366`; `chat_pipeline.R:141-188`; `stream_pump.R:118-120`. Abort exists for async jobs (`cancel_job()`, `async_chat.R:434-449`) |
| V-25 | llm.api has no retry and never sets `is_error`; its agent requests are non-streaming | CONFIRMED | Case-insensitive grep: `retry` 0 matches and `is_error` 0 matches in `llm.api/R`; `agent.R:694-702` (`curl_fetch_memory`); `max_turns = 20L` at `:85` |
| V-26 | aisdk: "no handling of thinking blocks or signatures … `thinking` appears only in request configuration" | CORRECTED | Thinking deltas are handled as reasoning text (`sse_aggregator.R:515-539`). Signatures and `redacted_thinking` are never captured (package-wide grep). Tool-input deltas are accumulated silently (`:150-154`), so the §12 cell was changed from "?" to ✗ |
| V-27 | aisdk runs code in a `callr` subprocess, "not in-memory computation, so REQ-22 is not met" | CORRECTED | In-process evaluation exists: `SharedSession$execute_code()` (`shared_session.R:176-207`), `SandboxManager$execute()` / `create_r_code_tool()` (`sandbox.R:59-60, 158-170`), and a `ChatSession` env that the user may supply (`session.R:114`). Only `r_eval` uses a subprocess. REQ-22 is now rated partially met: not the caller's env by default, and aisdk writes hidden bindings into the session env |
| V-28 | aisdk timeouts: "blocking reads make idle checks moot" (§13) | CORRECTED | The idle, first-byte and connect limits are libcurl options (`low_speed_limit`/`low_speed_time`, `server_response_timeout`, `connecttimeout`; `utils_http.R:226-318`), so they work under blocking reads. The total limit is off by default |
| V-29 | aisdk ids use `stats::runif()` at `session_event_store.R:48, 141`; retry-after is uncapped | CONFIRMED (line fixed) | `runif` is at `:50` and `:141`. The store root defaults to `getwd()/.aisdk/sessions` and can be overridden (`:23-31`). Uncapped retry: `utils_http.R:620-632` |
| V-30 | btw evaluates in `global_env()` with no timeout; sub-agents are synchronous | CONFIRMED | `btw/R/tool-run.R:121-125` (default `.envir = global_env()`), `:232-238`, `:399` (tool calls `impl(code)`); grep for `setTimeLimit|timeout` in `tool-run.R` finds 0; `tool-agent-subagent.R:480, 804` |
| V-31 | corteza copies `.h_NNN` handles into `globalenv()` and accepts the NOTE | CONFIRMED | `corteza/R/handles.R:135-160` (the comment states it) |
| V-32 | mall coerces invalid answers to `NA`; `llm_vec_verify()` returns a factor | CONFIRMED | `mall/R/m-vec-prompt.R:44-62`; `llm-verify.R:67-82` |
| V-33 | gptstudio has no tool calling; openai forbids `stream = TRUE`; rollama does not execute tools | CONFIRMED | grep `tool_calls|tool_use|function_call` in `gptstudio/R` finds 0; `openai/R/create_chat_completion.R:116-118`; `rollama/R/chat.r:181-216` |
| V-34 | "A grep for 'steer' over all eleven main packages found zero matches" | CORRECTED | A case-insensitive grep over 13 packages finds `mcptools/R/session.R:182`, an unrelated comment. The conclusion (no steering feature anywhere) stands |
| V-35 | "Only llm.api splits 5-minute and 1-hour cache writes" | CONFIRMED, QUALIFIED | grep `ephemeral_1h|write_1h` matches only `llm.api/R/{cost,agent}.R`. ellmer can *request* `cache = "1h"` (`provider-claude.R:85`) but prices all writes at 1.25× (`:536-540`) |
| V-36 | chattr `mget()`s every global (`ch-context.R:58-61`) | CONFIRMED (lines fixed) | `chattr/R/ch-context.R:59-62` |
| V-37 | The steering hack produced `assistant(tool_use) → user(STEER) → user(tool_result)` | CONFIRMED (wire) | `log_e050b/requests.jsonl` #13. That the real API rejects this remains LIKELY: Anthropic merges consecutive user turns, but then the text precedes the `tool_result` blocks |

**Not re-verified in this pass (UNCERTAIN, or relying on other reports):**
- llm.api's Claude-plan OAuth conflicting with Anthropic's terms (policy claim, from track 10).
- curl's PIPEWAIT serialising `parallel_chat()` on HTTP/1.1, and coro's 2–3× CPU cost (report 15).
- Real HTTPS / HTTP-2 providers batching like the mock.
- The API rejecting the E11 wire order.
- btw's 46,235-character tool schema and its 70-package dependency closure (track 10 scripts, not re-run).
- corteza's v2 flat JSONL (track 10).
- Provider API facts cited from reports 07, 08 and 09.
- Whether ellmer's use of the `fc_` item id as `call_id` matters on the wire.

**Net effect on the conclusions.** None of the corrections weakens the case for S-10. The ellmer findings
that carry the argument all held on re-run: blocking sync transport, quadratic accumulation, interrupt and
replay behaviour, the total timeout, redacted-thinking aborts, cross-provider replay, missing argument
validation, the unbounded non-steppable loop, and shared-callback clones. The async-path TTFT block adds to
them. The corrections concern fairness to other packages:
- aisdk does evaluate in-process, handles thinking text, and has well-built timeouts.
- tidyllm's Ollama path catches tool errors, and it has `cancel_job()`.
- ellmer's approval callback can prompt, its usage summary is global by design, and Mistral does read a
  rate-limit header.
- agenticr's UTF-8 failure is an abort, not a silent drop.
- `parallel_chat()` takes per-conversation prompts.

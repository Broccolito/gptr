# Track 15 — Concurrency and sub-agents in R

Research date: 2026-09-29. Requirements covered: REQ-32 (sub-agents), REQ-33 (parallel execution), REQ-34 (cross-LLM collaboration), REQ-35 (workflows as R control flow), with side effects on REQ-02/03 (CRAN, cross-platform), REQ-22 (evaluation environment) and REQ-38 (interrupt). Decides open decision **D-13 (concurrency engine)** and refines **D-04** and **D-12**.

Environment used for every experiment: macOS 26 (Darwin 25.6.0, arm64, 8 cores, 24 GB RAM), R 4.4.3, always `Rscript --vanilla`. Installed versions: curl 7.0.0 (libcurl 8.14.1), httr2 1.2.2, processx 3.8.6, callr 3.7.6, ps 1.9.3, later 1.4.8, promises 1.5.0, coro 1.1.0, cli 3.6.6, future 1.70.0, parallelly 1.46.1, httpuv 1.6.17, jsonlite 2.0.0. Installed into the private library for testing: mirai 2.6.1, nanonext 1.8.1, mori 0.2.2 (built from source), webfakes 1.4.0, lobstr 1.2.0, bench 1.1.4, crew 1.3.0, future.mirai 0.10.1. The R 4.4 CRAN binary repository is frozen, so current CRAN versions are newer: mirai 2.7.3 (2026-09-24), nanonext 1.10.3, httr2 1.3.0, curl 8.0.0 (8.1.0 is listed in the GitHub NEWS), callr 3.8.0, processx 3.9.0, parallelly 1.48.0, ellmer 0.5.0 (executed: `available.packages()` against cloud.r-project.org, see §5.0; ellmer re-checked by the verifier).

**Measurement caveat.** Other research tracks were running on the same machine. `uptime` load averages ranged from about 20 to 150 during this work (executed: `uptime` -> "load averages: 149.52 66.09 38.25" at 18:43, "20.10 33.87 41.74" at 19:01, "111.40 58.27 48.62" at 19:06), and macOS memory compression made OS RSS numbers meaningless (a 381 MB vector showed 140-484 MB RSS on different runs). Wall-clock figures are therefore medians or repeated runs, relative comparisons are always within one run, and memory claims use R's own accounting (`gc()` Vcells, object addresses, serialized size) rather than RSS. Nothing was run on Windows or Linux. No paid model API call was made; the `claude` and `codex` CLIs were only asked for `--help`/`--version`.

**Prior work.** A previous researcher on this track left, in `scratchpad/work/15/`, a webfakes-based mock server (`mock_llm.R`), an SSE parser (`sse.R`), a curl-multi prototype (`a1_curl_multi.R`) that reported `[FAIL]`, and a private library with mirai and friends. No report draft existed. I reran everything: the SSE parser is kept (verified by use in every prototype below); the `[FAIL]` was caused by curl's `PIPEWAIT` default, diagnosed and fixed in §2.2; the webfakes mock works but I added a zero-dependency base-R mock server because the task asked for an R mock and httpuv cannot stream (§2.1).

---

## 1. Executive summary

- **R can run N agent loops concurrently in one process for everything that is I/O.** Measured: 6 SSE streams whose schedules total 8.76 s finished in 2.29-2.30 s (slowest stream 2.25 s); 20 streams of 2.2 s each finished in 2.33-2.34 s; CPU use 0.4-0.6 s. Tool execution (evaluating R code) is inherently one-at-a-time on the main thread. VERIFIED (§5.2).
- **Headline feature works: in-process ("inline") sub-agents read the caller's objects with zero copy.** Five inline agents, each streaming an Anthropic-shaped response, calling an `r` tool against a shared 381 MB vector and streaming a second turn, finished in 5.2-5.3 s concurrently versus 14.0-14.5 s sequentially. Tool calls never overlapped; tokens that arrived during a 0.5 s tool were buffered and delivered within 50 ms after it; the vector's address seen from every agent equalled the caller's. VERIFIED (§5.4).
- **D-13 decision: build the engine on `curl` multi handles directly, driven by one gptr-owned reactor loop that waits with `processx::poll()` on `processx::curl_fds(curl::multi_fdset(pool))` plus all child-process pipes.** One wait call covers HTTP streams, worker processes and CLI agents; verified with 2 inline + 2 worker + 1 CLI agent interleaving in one loop (2.08 s). No coro, no promises, no later needed for the core. VERIFIED (§5.9).
- **Critical pitfall: since curl 6.1.0 every handle has `CURLOPT_PIPEWAIT` on by default.** On a shared pool, streams to an HTTP/1.1 host (local Ollama, llama.cpp, the mock) wait until the first long response completes: wall 3.4-3.5 s instead of 2.3 s for the 6-stream workload (and against a keep-alive HTTP/1.1 mock the verifier saw 4 streams fully serialized, 4.9-5.1 s instead of 1.3 s, §2.2). This affects `curl::multi_add`, `httr2::req_perform_parallel()` and `httr2::req_perform_promise()` alike, and therefore also ellmer's `parallel_chat()`. Fix: `handle_setopt(h, pipewait = 0L)` (or `req_options(req, pipewait = 0L)` in httr2). `httr2::req_perform_connection()` is not affected (own handle per connection). VERIFIED (§2.2, §5.2, §5.3).
- **httpuv cannot be the streaming mock**: its response body is one string/raw vector sent at once (5 tokens produced over 1.5 s arrived as one 140-byte chunk at 1.53 s). I wrote a base-R mock SSE server (`serverSocket()` + `socketSelect()`, about 150 lines, no dependencies) that serves many concurrent streams from one R process; it is suitable for gptr's own test suite. VERIFIED (§5.1).
- **Out-of-process workers, measured start-up:** `callr::r_session$new()` 0.25 s (0.45 s under heavy load), warm `$run()` round trip 29 ms; `callr::r_bg()` start+result 0.25 s; `mirai::daemons(1)` + first task 0.89 s, warm mirai round trip < 1 ms, `mirai_map()` over 8 items 2 ms; fork via `parallel::mcparallel()` 7 ms; `future` multisession plan + first value 0.61 s. VERIFIED (§5.6).
- **Shipping a 496 MB numeric vector to a worker** (5 reps, median): callr by value 1.38 s; mirai 2.6.1 by value 3.5-3.8 s (slower than callr on this machine); fork 0.23 s (no copy); `mori::share()` 0.17 s once, then 0.33 s per mirai or callr round trip, because the shared object serializes to 134 bytes. VERIFIED (§5.6).
- **mori (new, 2026-07, by the mirai author) gives cross-platform shared-memory transport**: POSIX shm on Unix, Win32 file mapping on Windows, ALTREP-backed, integrated with mirai and with any `serialize()` (so callr too). An S4 `dgCMatrix` whose `@i/@p/@x` slots were shared serialized to 572 bytes and a worker read it with a 4.2 MB heap. **But on R 4.4.3 + mori 0.2.2 most ordinary operations (`v[5]`, `head`, `range`, `var`, `sort`, `crossprod`, `%*%`, Matrix ops, `print`) materialize a private copy in the process that touches the vector**; only `sum`, `mean`, `max`, `length` and element-wise arithmetic stayed zero-copy, and element-wise arithmetic was very slow (2.3 s for 2e6 doubles). mori saves transfer time, not per-worker memory. VERIFIED (§5.7).
- **Forking is the only zero-copy way to give a worker a 5 GB object on Unix, but should be opt-in only**: not available on Windows; R's own documentation "strongly discourages" `mcfork()` in GUIs (RStudio) and in any multi-threaded R process, which a gptr session usually is; `parallelly::supportsMulticore()` returns FALSE when `RSTUDIO=1`. In Rscript a fork while the parent had live curl streams worked (3 children in 0.13 s, parent stream intact). VERIFIED (§2.8, §5.8).
- **mirai pitfall: locally launched daemons do not inherit the parent's `.libPaths()`.** With mirai installed in a non-default library the dispatcher failed to start and `daemons()` waited indefinitely ("initial sync with dispatcher [590 secs elapsed]"). callr passes `libpath = .libPaths()` by default. Also: callr defaults to `user_profile = "project"`, so a worker started in a project with an `.Rprofile` (like this repo's broken one) sources it; gptr must pass `user_profile = FALSE`. VERIFIED (§2.6).
- **`new.env(parent = caller)` gives zero-copy reads and local writes** (read of 381 MB: heap +1.0 MB, `tracemem` 0 copies, same address; a write created a local 381 MB copy and left the caller untouched). **It does not stop**: `<<-` to an existing name, caller-defined functions using `<<-`, reference objects (environments, R6, Seurat's environments), data.table `:=`, `assign(envir = globalenv())`, `<<-` to a brand-new name (lands in globalenv), and the process-global RNG state. VERIFIED (§5.5).
- **A binding-lock guard** (lock every unlocked binding of the caller for the duration of a tool call, unlock afterwards) turns `<<-` into the error "cannot change value of locked binding"; new bindings are detected by a before/after name diff; reference-object mutation cannot be prevented. Cost is about 10-15 µs per binding (19-33 ms for 2000 bindings under load). Pitfall found: a top-level `for` index is an unboxed "immediate" binding on which `lockBinding()` fails with "bad binding access"; re-assigning the value first fixes it. VERIFIED (§5.5, §5.13).
- **Per-agent RNG streams**: swapping an L'Ecuyer-CMRG `.Random.seed` in and out around each tool call gives every agent reproducible numbers independent of interleaving and leaves the user's RNG stream untouched. VERIFIED (§5.12).
- **Ctrl-C works everywhere measured.** In a non-interactive R session SIGINT surfaces as an `interrupt` condition; latency was < 10 ms in `Sys.sleep`, `curl::multi_run`, `curl_fetch_memory`, httr2 blocking stream reads and `later::run_now`, 46 ms in a pure-R loop, 0.20 s in `processx::poll`, 0.26 s in `callr r_session$run`, 0.29 s waiting on a mirai. An `on.exit()` cleanup cancelled 4 transfers and `kill_tree()`-ed 7 children and grandchildren in 190-253 ms. After SIGKILL of the session, `supervise = TRUE` children died but their own grandchildren and an unsupervised worker survived. VERIFIED (§5.10, §5.11).
- **Background agents at the console are feasible**: with an idle interactive R prompt, a stream serviced through `later::later_fd()` advanced 0 → 7 → 20 → 30 tokens across three user commands, and a verifier check confirmed tokens are consumed in real time while the prompt is idle (§2.5). This enables `gptr(..., background = TRUE)`. VERIFIED on macOS only (§5.14).
- **External CLI agents** (`claude` 2.1.261, `codex-cli` 0.157.0 installed) run as parallel sub-agents through processx with JSONL on stdout; a runner with 3 slots finished 5 fake-CLI agents (8.8 s nominal) in 3.08 s, isolating one failure and one timeout and aggregating usage. Prompts must go through stdin (Windows command-line limit, `.cmd` shim quoting). VERIFIED with fake CLIs (§5.15); CLI flags VERIFIED from local `--help`; event shapes VERIFIED from official docs for both Claude and Codex (the Codex non-interactive page now shows sample `--json` lines, see §2.9).
- **Agent definition files**: one loader reads Claude Code `.claude/agents/**/*.md` (recursive), Pi `.pi/agents/*.md` (flat) and gptr `.gptr/agents/**/*.md`, with gptr > Claude > Pi precedence; tested on Pi's four real agent files plus edge cases. Bug class found: `meta$mode` partially matches `model` via `$`; always use `[[`. VERIFIED (§5.16).
- **Prior art confirms the defaults**: Pi's subagent extension caps 8 tasks, 4 concurrent, 50 KB output per task, SIGTERM then SIGKILL after 5 s (VERIFIED in source; note the SIGKILL is guarded by `!proc.killed`, which Node sets as soon as SIGTERM is delivered, so in practice the fallback does not fire — gptr should key its fallback on "process still alive", §2.14); Claude Code caps nesting at 3 and concurrency at 20 (VERIFIED in docs); Pi's agent loop has a per-tool `executionMode: "sequential"` flag that forces one-at-a-time execution, exactly what gptr's `r` tool needs (VERIFIED in source).
- **Recommended R API** (consistent with S-1 and D-28): `gptr(prompt, agents = list(...))`, `gptr(prompt, x, parallel = n)`, `gptr_agent()`, `gptr_parallel()` (deferred `gptr()` calls evaluated concurrently), `gptr_map()`, `gptr_panel()`, `gptr_review()`, `gptr_debate()`, `gptr_wait()`, `gptr_cancel()`, `gptr_usage()`; results are `gptr_result`/`gptr_results` objects; modes `inline` (default), `worker` (callr), `cli`; model-facing tool `agent`. §4.
- **Packages**: Imports `curl` (already a hard dependency of httr2), `processx`, `callr` (adds R6/processx, both already present, and, from callr 3.8.0 on current CRAN, `otel` (>= 0.2.0), which itself has no hard dependencies), `jsonlite`, `cli`; Suggests `later` (background mode), `promises` (Shiny), `mirai` + `mori` (optional accelerated/shared-memory workers), `parallelly` (core detection, or a 10-line own version). Not recommended: `coro` (about 2-3x the CPU of the curl-multi reactor and 4-8x that of round-robin httr2 polling in the streaming test, no benefit over explicit state machines), `future` (the user owns `plan()`), `crew` (heavy dependency tree). §4.12.

---

## 2. Findings

### 2.1 Mock streaming server: httpuv cannot stream; base R can

- httpuv's documented response `body` is "A string (or 'raw' vector) to be sent as the body of the HTTP response" (executed: `tools::Rd2txt(tools::Rd_db("httpuv")[["startServer.Rd"]])`), and NEWS has no chunked/streaming support (executed: `grep -i "stream\|chunk" httpuv/NEWS.md` -> only Rook error-stream items). VERIFIED.
- Experiment `p0_httpuv_nostream.R`: an httpuv handler returning a promise that accumulates 5 SSE events at 0.3 s intervals. Client arrival log: `1.53s: chunk of 140 bytes holding 5 token events` (and 1.54 s on the rerun). The whole body arrives at once. VERIFIED.
- `webfakes` (CRAN, used by httr2's own tests) supports `res$send_chunk()` + `res$delay()` and the previous researcher's `mock_llm.R` works (4 CLI curl clients in parallel: 1.29 s for 1.2 s streams; executed `a1b_server_check.R`). VERIFIED.
- I wrote `mock_sse_base.R`: base R `serverSocket()`, `socketAccept(blocking = FALSE)`, `socketSelect()` with a timeout equal to the next due token, per-client state (read request head/body, then emit a schedule of events), running in a `callr::r_bg()` child. Endpoints `/ping`, `/sse?id=&n=&delay=&first=`, and `POST /v1/messages` returning an Anthropic-shaped stream (message_start, content_block_start/delta/stop, optional `tool_use` block whose `input_json_delta` is split into 3 fragments, message_delta with `stop_reason` and usage, message_stop). It served 20 concurrent streams with correct timing (§5.2). VERIFIED. Recommendation: ship this (or a variant) in `tests/testthat/helper-mock-server.R`; it needs only base R + jsonlite in the child, and skip it on CRAN (binding ports may be blocked).

### 2.2 In-process HTTP concurrency and the PIPEWAIT pitfall

- The previous draft's `[FAIL]`: stream A ran alone, then B, then C-F together (executed `a1_curl_multi.R` -> "WALL: 5.37s ... [FAIL]"). Independent CLI curl clients were concurrent (1.29 s), so the server was not the cause.
- Diagnosis (`a2_pool_diag.R`, 4 streams of 1.2 s): default pool 2.46 s with first bytes of streams 2-4 at 1.23 s; `new_pool(host_con = 100)` 2.51 s (same); `new_pool(multiplex = FALSE)` 1.23 s; handle `pipewait = 0` 1.24 s; `forbid_reuse + fresh_connect` 1.23 s; `http_version = 1.1` 1.23 s. VERIFIED. Verifier re-runs (same script, webfakes keep-alive mock, load ~22) were *worse*: default pool 4.94 s and 5.11 s with first bytes at 0 / 1.24 / 2.47-2.54 / 3.71-3.87 s (streams fully serialized, each waiting for the previous one), `host_con = 100` 4.14-5.03 s; every fix variant 1.25-1.36 s. So against a keep-alive HTTP/1.1 server the default can serialize all N streams, not just delay streams 2..N behind stream 1.
- Cause: curl NEWS 6.1.0 "Enable CURLOPT_PIPEWAIT by default to prefer multiplex when possible" and "Enable setting max_streams in multi_set(), default to 10" (read locally in `curl/NEWS` and at https://github.com/jeroen/curl/blob/master/NEWS). With PIPEWAIT, a new transfer to a host with a pending connection waits to learn whether that connection can multiplex; over plain HTTP/1.1 it only learns this when the first (long) response ends. `curl::new_pool()` signature: `new_pool(total_con = 100, host_con = 6, max_streams = 10, multiplex = TRUE)`. VERIFIED (mechanism LIKELY, behaviour VERIFIED).
- httr2 is affected wherever it uses a shared pool: `req_perform_promise()` (default 3.43-3.45 s vs 2.31 s with `pipewait = 0`) and `req_perform_parallel()` (3.42-3.47 s vs 2.30-2.32 s). `req_perform_connection()` is not (2.35-2.44 s either way) because each connection has its own handle. VERIFIED (`p2_httr2_variants.R`).
- ellmer 0.4.0's `parallel_chat()` goes through `parallel_turns()` -> `req_perform_parallel(reqs, max_active = max_active, on_error = on_error)` without touching `pipewait` (executed: printed `ellmer:::parallel_turns`), so against an HTTP/1.1 endpoint it has the same first-request stall. LIKELY (inferred from code plus the httr2 measurement). Still true in ellmer 0.5.0 (current CRAN): `R/parallel-chat.R` calls `req_perform_parallel(reqs, max_active = max_active, on_error = on_error)` and no ellmer or httr2 1.3.0 source file mentions `pipewait` (verifier: grep of the CRAN source tarballs).
- For HTTP/2 providers (Anthropic, OpenAI and Google APIs are served over HTTPS where libcurl negotiates HTTP/2 by ALPN), PIPEWAIT's purpose is to multiplex many streams over one connection (up to `max_streams = 10` per connection). With `pipewait = 0` the first few concurrent transfers may open separate TLS connections; once HTTP/2 is known, later transfers multiplex. That is acceptable for up to a few dozen agent streams. LIKELY (not measured against a real provider).

Measured matrix (6 streams, schedules 1.00-2.25 s, sum 8.76 s; second run, load 50-110):

| API | pipewait default | pipewait = 0 | CPU (pw=0) | Streams? |
|---|---|---|---|---|
| curl `multi_add(data=)` + `multi_run()` | 3.51 s | **2.30 s** | 0.44 s | yes, push callbacks |
| httr2 `req_perform_connection(blocking = FALSE)` round-robin `resp_stream_sse()` | 2.44 s | 2.32 s | 0.11 s | yes, pull; 217 polls |
| coro `async_generator` + `later::later_fd(resp$body$get_fdset())` (ellmer's `chat_perform_async_stream`) | 2.53 s | 2.40 s | 0.81 s | yes |
| httr2 `req_perform_promise()` x6 + `later::run_now()` | 3.45 s | 2.31 s | 0.05 s | no (whole body) |
| httr2 `req_perform_parallel()` x6 | 3.42 s | 2.32 s | 0.03 s | no (whole body) |

- Non-blocking httr2 connections do not busy-wait: curl 6.2.3 NEWS "Non blocking connections now wait for 10ms before returning no data to prevent busy waiting". Consequence: round-robin polling N idle connections costs up to N x 10 ms per sweep, adding latency for large N. VERIFIED (NEWS read locally; CPU measured; verifier measured 20 `resp_stream_sse()` calls on an idle non-blocking connection at 11.1 ms each).
- ellmer's async streaming pattern, verbatim from `ellmer:::chat_perform_async_stream` (executed: printed): `resp <- req_perform_connection(req, blocking = FALSE)` ... `fds <- resp$body$get_fdset(); await(promises::promise(function(resolve, reject) { later::later_fd(resolve, fds$reads, fds$writes, fds$exceptions, fds$timeout) }))`. httr2's own promise path is `ensure_pool_poller()`: `curl::multi_run(0, pool = pool)` then `later::later_fd(func = poll_pool, readfds = fds$reads, writefds = fds$writes, exceptfds = fds$exceptions, timeout = fds$timeout)` (executed: printed `httr2:::ensure_pool_poller`). VERIFIED.

### 2.3 Interleaving N agent loops as state machines (the inline design)

Prototype `p3_inline_agents.R` (full code §5.4). Each agent is an environment holding `state` (`queued`, `streaming`, `tools`, `ready`, `done`, `error`), its message list, an SSE parser, an Anthropic event assembler (text deltas, `input_json_delta` accumulation, stop reason, usage), usage totals and its own overlay environment `new.env(parent = caller)`. The reactor:

1. starts calls for `queued` agents while fewer than `max_active` are active, and for `ready` agents (tool results appended);
2. if the global tool FIFO is non-empty, runs exactly **one** tool call, appends the `tool_result`, flips the agent to `ready` when all its calls are done, then drains the network with `curl::multi_run(timeout = 0)`;
3. otherwise waits in `processx::poll(list(processx::curl_fds(curl::multi_fdset(pool))), ms)` and then `curl::multi_run(timeout = 0)` to fire the data/done callbacks.

Results over four runs (load 20-150): concurrent (max_active 5) 5.18-6.06 s; max_active 2 8.72-10.31 s; sequential (max_active 1) 14.04-14.83 s. Tool calls in execution order never overlap (e.g., addr 1.85-1.85, stats 1.96-2.16, quant 2.34-2.35, sizes 2.58-3.08, write 3.29-3.29). During `sizes`' `Sys.sleep(0.5)` tool no token callbacks ran (R was busy) and 13-14 tokens were delivered within 50 ms after the tool finished: the kernel and libcurl buffer the streams, nothing is lost. Isolation: caller's `big` untouched (length and address), agent `write` had a local 3-element `big`, agent `addr` returned `identical(lobstr::obj_addr(big), '<caller address>')` -> `[1] TRUE`. VERIFIED.

Implications:
- Wall time ≈ the slowest agent's own critical path plus queueing behind other agents' tool calls. A long-running R tool (a 3-minute model fit) stalls the tool queue of every inline agent; their HTTP streams keep buffering meanwhile. Heavy compute should be routed to worker mode or given a timeout (`setTimeLimit(elapsed = )` around the tool evaluation).
- Nested sub-agents fit the same reactor: the `agent` tool can register child agents and park the parent in a `waiting_children` state instead of blocking inside the tool (the same idea as Pi's durable "subagent tool creates a child conversation owned by the tool's task", see report 06 §2.5). If the model instead calls `gptr_parallel()` from inside R code (the `r` tool), that call runs a nested reactor synchronously: correct, but sibling agents pause for its duration.
- coro/promises are not needed. The coro variant used about 2-3x the CPU of the curl-multi variant and 4-8x that of the round-robin httr2 variant for the same streams (§2.2 table: 0.81 s vs 0.44 s vs 0.11 s; verifier re-runs 0.61-0.92 s vs 0.26 s vs 0.10-0.21 s). In one verifier run at load ~60-70 it was also the only variant whose wall time collapsed (5.33 s default / 2.64 s with `pipewait = 0`, every stream finishing together); it matched the other variants (2.34-2.48 s) on two re-runs at load ~22.

### 2.4 One reactor for all modes

`processx::poll(processes, ms)` accepts "A list of connection objects or 'process' objects" and `processx::curl_fds(fds)` "Create[s] a pollable object from a curl multi handle's file descriptors" (executed: `tools::Rd2txt` of `poll.Rd`, `curl_fds.Rd`). processx NEWS: "Fix a potential failure when polling curl file descriptors on Windows" and "Allow polling more than 64 connections on Windows, by using IOCP" (read locally), so this works on Windows too (LIKELY; not run). `p10_mixed.R` ran 2 inline agents, 2 callr worker agents that stream from the provider themselves and report JSONL on stdout, and 1 CLI-like process, all in one `processx::poll()` loop: WALL 2.08 s, 45 source switches in arrival order, first arrivals `0.45:wk1 0.45:wk2 0.56:wk1 0.57:wk2 0.57:in1 0.58:in2 0.65:cli ...`. Spawning children blocks the loop briefly (inline first token at 0.57 s instead of ~0.3 s); data is buffered meanwhile. VERIFIED.

### 2.5 Background agents while the user keeps working

`later` runs callbacks "only ... when there is no other R code present on the execution stack; i.e., when R is sitting at the top-level prompt" (later_fd.Rd, read locally). `p13_background_console.R` drove `R --interactive` over a pipe, started a curl stream serviced by a self-re-arming `later::later_fd()` callback, then sent user commands: "started; tokens so far: 0", "user command 1 ... tokens so far: 7", "user command 2; tokens so far: 20 done: FALSE", "user command 3; tokens so far: 30 done: TRUE". VERIFIED on macOS. (Those counts alone cannot distinguish "serviced while idle" from "drained once per command", because one `multi_run()` drains everything buffered. The verifier added a check, `p13b_idle_check.R`: with no user command for 5 s, the callback ran 34 times and tokens were recorded at 0.40 / 1.29 / 2.29 / 3.29 s, i.e. in real time while the prompt was idle; stream done before the first command at 4.82 s. VERIFIED.) Because later only runs at top level, a background agent's R tool calls would execute between user commands, never in the middle of one. Windows: `later_fd()` "readfds: Integer vector of file descriptors, or Windows SOCKETs" and uses `WSAPoll` on Windows, so curl sockets work; processx pipes are not sockets, so they presumably cannot be watched this way (LIKELY, inferred from the docs, not tested; use a periodic `later::later()` timer calling `processx::poll(ms = 0)`). RStudio runs later callbacks when idle (LIKELY); Positron, Jupyter/IRkernel and knitr: UNCERTAIN, needs testing.

### 2.6 Out-of-process workers: callr, mirai, future, crew

Measured (`p4_workers.R`, load ~45; `p4b_transfer.R`, 5 reps, load ~22):

| Operation | Time |
|---|---|
| `callr::r_session$new()` (wait = TRUE) | 0.253 s (0.445 s at load 150) |
| `r_session$run(function() 1)` warm | 0.029 s (0.061 s at load 150) |
| `callr::r_bg(function() 1)` start + wait + result | 0.246 s |
| `callr::r(function() 1)` | 0.253 s |
| `mirai::daemons(1)` (dispatcher) + first `mirai(1)[]` | 0.890 s |
| `daemons(4, dispatcher = FALSE)` + 4 tasks | 0.633 s |
| warm `mirai(1)[]` | < 1 ms (printed 0.000) |
| `mirai_map(1:8, function(i) i)[]` warm | 0.002 s |
| `parallel::mcparallel(1)` + `mccollect()` (fork) | 0.007 s |
| `future::plan(multisession, workers = 2)` + first value | 0.606 s |
| **496 MB vector**: `serialize(x, NULL)` xdr / native | 0.64 s / 0.16 s |
| callr `r_session$run(sum, list(x))` (by value) | 1.38 s (1.30-1.54) |
| `mirai(sum(x), x = x)[]` 1 daemon, dispatcher | 3.85 s (3.00-4.61) |
| same, `dispatcher = FALSE` | 3.47 s (2.01-3.64) |
| `mcparallel(sum(x))` (fork, no copy) | 0.23 s |
| `mori::share(x)` (one copy into shared memory) | 0.17 s |
| `mirai(sum(xs), xs = xs)[]` / callr with `xs` shared | 0.33 s / 0.33 s |
| `sum(x)` locally (compute baseline) | 0.19 s |
| `mirai::everywhere()` broadcast of x to 2 daemons | 29 s (single run at load ~45); verifier re-run 24.4 s at load ~25-60, so not an outlier: large `everywhere()` broadcasts are very slow with mirai 2.6.1 on this machine |

- callr's `r_session$run()` handles interrupts: callr NEWS "`r_session$run*()` handle interrupts properly. It tries to interrupt the background process fist, kills it if it is not interruptible, and then re-throws the interrupt condition" (read locally). VERIFIED text.
- callr `r_bg()` signature (executed): `r_bg(func, args = list(), libpath = .libPaths(), repos = default_repos(), stdout = "|", stderr = "|", poll_connection = TRUE, error = getOption("callr.error", "error"), cmdargs = c("--slave", "--no-save", "--no-restore"), system_profile = FALSE, user_profile = "project", env = rcmd_safe_env(), supervise = FALSE, package = FALSE, arch = "same", ...)`. `r_session_options()` defaults: `user_profile = project`, `system_profile = FALSE`, `supervise = FALSE` (executed). **`user_profile = "project"` means a worker started in a project directory sources that project's `.Rprofile`** (this repo's sources a missing `renv/activate.R`). gptr must pass `user_profile = FALSE` and keep `libpath = .libPaths()` (so renv libraries still work). VERIFIED (defaults); consequence LIKELY.
- **mirai library-path pitfall**: with mirai only in the private library, `daemons(1)` printed "mirai: initial sync with dispatcher [10 secs elapsed]" every 10 s up to 590 s and never returned (the dispatcher child could not load mirai). Exporting `R_LIBS=<private lib>` before starting R fixed it. VERIFIED (mirai 2.6.1). mirai 2.7.0 "Dispatcher reimplemented as a thread for lower overhead, removing the separate dispatcher process" (https://mirai.r-lib.org/news/index.html), but daemons are still separate R processes that must load mirai, so the rule stands: propagate `.libPaths()` (e.g., `Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))` before `daemons()`) and never wait without a timeout. VERIFIED for 2.7.3 from the CRAN source: local daemons are started by `launch_daemon <- function(args) system2(.command, args = c("-e", shQuote(args)), wait = FALSE)` with `args` = `mirai::daemon(...)` (`R/daemons.R`), and the only `.libPaths()` propagation in the package is in the Posit Workbench launcher (`R/launchers.R`). Only the failure symptom will differ (no dispatcher process to hang on; daemons never connect).
- mirai 2.6.1 by-value transfer of 496 MB was 2.5x slower than callr's temp-file route on this machine. mirai 2.7.0 NEWS: "Fixes transfer of large data (>~2GB) on macOS and Windows". Re-measure with 2.7.3 before relying on either number. UNCERTAIN (version-specific).
- mirai API (current docs, https://mirai.r-lib.org/reference/daemons.html): `daemons(n, url = NULL, remote = NULL, dispatcher = TRUE, ..., sync = FALSE, seed = NULL, memory = NULL, serial = NULL, tls = NULL, pass = NULL, .compute = NULL)`; `daemons(0)` resets: "Any as yet unresolved 'mirai' will return an 'errorValue' 19 (Connection reset)"; "If the host session ends, all connected dispatcher and daemon processes automatically exit as soon as their connections are dropped" (verbatim from the reference page and the 2.7.3 source; the earlier wording here was a paraphrase). `stop_mirai()` returns a logical "TRUE if the cancellation request was successful ... Will always return FALSE if not using dispatcher" (logical return added in mirai 2.0.0, not 2.6.0); 2.6.0: `race_mirai()` "now returns the integer index of the first resolved 'mirai'". 2.7.0: `memory` budget (MB, requires dispatcher) and `try_mirai()`. VERIFIED (docs + NEWS in the 2.7.3 source tarball).
- future: `plan()` is user-owned global state; gptr must not call it. multisession start-up 0.61 s. Not needed for gptr. VERIFIED (timing).
- crew 1.3.3 Imports: cli, collections, data.table, later, mirai (>= 2.7.0), nanonext, processx, promises, ps, R6, rlang, stats, tibble, tidyselect, tools, utils (executed: `available.packages()`). It is a task-queue/autoscaling layer for pipelines (targets); far too heavy for gptr's needs. VERIFIED (deps).

### 2.7 mori: shared memory for workers, and its limits

- DESCRIPTION (installed 0.2.2): "Share R objects across processes on the same machine via a single copy in 'POSIX' shared memory (Linux, macOS) or a 'Win32' file mapping (Windows). Every process reads from the same physical pages through the R Alternative Representation ('ALTREP') framework, giving lazy, zero-copy access. Shared objects serialize compactly as their shared memory name rather than their full contents." Depends R (>= 4.3); Suggests mirai, testthat; NeedsCompilation yes; no binary for R 4.4 (built from source). Exports `share`, `map_shared`, `shared_name`, `is_shared`, `prune_shared`. VERIFIED.
- `?share`: attributes stored alongside; "For any other object (environments, closures, language objects, 'NULL'), the input is returned unchanged"; "*Important*: ensure the return value of 'share()' is not garbage collected before a consumer can map its shared memory"; `saveRDS()` of a shared object writes only the name. VERIFIED.
- Coverage (executed): data.frame TRUE, list(num, chr) TRUE, environment FALSE, S4 `dgCMatrix` FALSE but its `@x` slot TRUE, user S4 object FALSE.
- S4 objects can be made shareable slot by slot: `ms <- m; ms@x <- share(m@x); ms@i <- share(m@i); ms@p <- share(m@p)` -> whole object serialized 572 bytes; in a callr worker `is_shared(m@x)` TRUE with a 4.2 MB heap. A recursive helper that assigned slots on a function argument lost sharing on all but the last slot (serialized 20 MB): R's copy-on-modify `duplicate()` materializes the ALTREP vector. Build shared objects by top-level slot assignment on an object with a single reference, then verify with `length(serialize(x, NULL))`. VERIFIED.
- **Materialization on access** (`p16g_materialise.R`, 2e6 doubles; after each op, is the vector still a ~134-byte reference?): stayed shared: `sum`, `mean`, `max`, `length`, `v * 2`; became a private 15.3 MB copy: `v[5]`, `v[1:10]`, `head`, `range`, `which.max`, `var`, `sort`, `crossprod`, `cumsum`, `is.na`, `v > 0.5`, `print(v[1:3])`. `.Internal(inspect())` also materializes. `v * 2` took 2.33 s (element-by-element ALTREP access) versus milliseconds normally. In a worker (`p16c_ops.R`, 153 MB vector and a shared dgCMatrix) the same pattern: heap +152.5 MB after `v[1:10]`, `range`, `quantile`, `var`, `sort`, `crossprod`, `%*%`; +38 to +57 MB after `Matrix::colSums(m)`, `m %*% v`, `m[1:10, 1:10]`; `is_shared()` still reported TRUE (it reports the wrapper, not whether a private copy exists). VERIFIED on R 4.4.3 + mori 0.2.2; may differ on R >= 4.5 (UNCERTAIN).
- Writes in a worker: `xs[1:3] <- 0` gave the worker a private copy (`is_shared` FALSE there); the parent's values were unchanged (0.79, 0.147, 0.625). VERIFIED.
- Conclusion: mori reliably removes the serialization/transfer cost (0.33 s versus 1.4-3.8 s for 496 MB) on all three platforms (Windows by documentation, not tested), but not the per-worker memory for typical analysis code. It is an optional accelerator for `worker` mode, not a substitute for inline mode.

### 2.8 Fork

- `?mcfork` (read locally): "It is _strongly discouraged_ to use 'mcfork' and the higher-level functions which rely on it (e.g., 'mcparallel', 'mclapply' and 'pvec') in GUI or embedded environments ... Child processes should never use on-screen graphics devices" and "It is _strongly discouraged_ to use 'mcfork' and the higher-level functions in any multi-threaded R process (with additional threads created by a third-party library or package). Such use can lead to deadlocks or crashes". A gptr session has libcurl (usually built with the threaded DNS resolver; not checked for the libcurl bundled with R's curl package here), later (background thread), possibly mirai/nanonext threads (2.7 dispatcher is a thread), data.table/arrow OpenMP threads. VERIFIED (doc text).
- `parallelly::supportsMulticore()` TRUE in Rscript, FALSE with `RSTUDIO=1` (executed). VERIFIED.
- `p11_fork_curl.R`: parent with a live curl stream forks 3 children that each make a fresh HTTP request and `sum()` a 153 MB vector: `3 forked children: pong,pong,pong | sums ok: TRUE | 0.13s`, `parent stream after the forks: 20/20 tokens, completed: TRUE`. VERIFIED (Rscript, macOS). One run of `p4_workers.R` ended with "Error while shutting down parallel: unable to terminate some child processes" at exit (leftover fork children).
- Verdict: fork is the only zero-copy way to give a worker a 5 GB object that mori cannot keep shared, so offer `mode = "fork"` as an opt-in on Unix terminals, refused under RStudio/Positron/GUIs (use `parallelly::supportsMulticore()`), never a default.

### 2.9 External CLI agents

- Installed: `claude` 2.1.261 (Claude Code), `codex-cli` 0.157.0 (executed `--version`).
- `claude --help` (executed, relevant lines): `-p, --print`; `--output-format <format>` "text" (default), "json" (single result), or "stream-json" (realtime streaming) (only with --print); `--input-format` "text" or "stream-json"; `--include-partial-messages`; `--verbose`; `--model <model>`; `--agents <json>`; `--agent <agent>`; `--allowedTools, --allowed-tools <tools...>`; `--disallowedTools`; `--tools <tools...>` (`""` disables all, "default" all); `--permission-mode <mode>` choices "acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan"; `--append-system-prompt`, `--system-prompt`; `--no-session-persistence` (only with --print); `--session-id <uuid>`; `--max-budget-usd` (only with --print); `--mcp-config`, `--strict-mcp-config`; `--json-schema`; `--effort`; `--bare`; `--settings`; `--add-dir`; `--fallback-model`; `--dangerously-skip-permissions`. VERIFIED.
- Claude Code headless docs (https://code.claude.com/docs/en/headless): exit code 0 on success and non-zero on failure; "When a failure happens inside the run, such as missing authentication, Claude Code prints the failure as the result on stdout"; `--bare` "reduce[s] startup time by skipping auto-discovery of hooks, skills, custom commands, subagents, installed plugins, MCP servers, auto memory, and CLAUDE.md" and does not use the subscription login (needs `ANTHROPIC_API_KEY`); stream-json "The last line of the stream is a `result` message with the final response text, cost, and session metadata"; `json` output includes `total_cost_usd`; SIGTERM -> exit 143 and the turn is left unfinished, "To end the turn instead, send SIGINT"; piped stdin capped at 10 MB; `system/init` first event (docs: "unless startup events precede it", i.e. `plugin_install` and `hook_started`/`hook_progress`/`hook_response` events, so a parser must not assume line 1 is `init`); `system/api_retry` events; subagent messages carry `parent_tool_use_id`. VERIFIED (docs). **Consequence for gptr**: plan (subscription) usage requires *not* passing `--bare`; to cancel a CLI sub-agent send SIGINT first (`p$interrupt()`), then `kill_tree()` after a grace period. Two further caveats from the same page (verifier): "`--bare` is the recommended mode for scripted and SDK calls, and will become the default for `-p` in a future release" (so the subscription path may later need an explicit opt-out flag; re-check per CLI version), and without `--bare` a `-p` session "runs the hooks in a project's `.claude/settings.json` and connects the servers in its `.mcp.json`, even in a folder you've never trusted" (a security consideration for CLI sub-agents started in the user's project). For `-p` the starting permission mode is Manual, so pass `--permission-mode` explicitly.
- `codex exec --help` (executed): `codex exec [OPTIONS] [PROMPT]`; "If not provided as an argument (or if `-` is used), instructions are read from stdin"; `-m, --model`; `-s, --sandbox <read-only|workspace-write|danger-full-access>`; `-C, --cd <DIR>`; `--skip-git-repo-check`; `--ephemeral` "Run without persisting session files to disk"; `--json` "Print events to stdout as JSONL"; `-o, --output-last-message <FILE>`; `--output-schema <FILE>`; `-c key=value`; `--dangerously-bypass-approvals-and-sandbox`. VERIFIED.
- Codex docs (https://learn.chatgpt.com/docs/non-interactive-mode, redirected from developers.openai.com/codex/noninteractive): event types `thread.started`, `turn.started`, `turn.completed`, `turn.failed`, `item.started`, `item.updated`, `item.completed`, `error`; item types agent_message, reasoning, command_execution, file_change, mcp_tool_call, web_search, todo_list; "By default, `codex exec` runs in a read-only sandbox"; `CODEX_API_KEY`: "To use a different API key for a single run, set `CODEX_API_KEY` inline" (e.g. `CODEX_API_KEY=<api-key> codex exec --json ...`). VERIFIED (docs; the earlier quotation "Set `CODEX_API_KEY` only for the specific Codex invocation" could not be found and was replaced). The official page itself shows sample lines, e.g. `{"type":"thread.started","thread_id":"0199a213-..."}`, `{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"bash -lc ls","status":"in_progress"}}`, `{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"..."}}`, `{"type":"turn.completed","usage":{"input_tokens":24763,"cached_input_tokens":24448,"output_tokens":122,"reasoning_output_tokens":0}}`. VERIFIED (docs; the third-party cheat sheet https://takopi.dev/reference/runners/codex/exec-json-cheatsheet/ is no longer needed). Note the extra `reasoning_output_tokens` usage field.
- CLI sub-agents cannot see the parent's in-memory objects directly. Option for later: gptr as an MCP server (D-14) whose stdio process relays tool calls over a local socket back to the parent reactor, which evaluates them between events. That would give CLI agents serialized access to the live session. UNCERTAIN (design idea, not prototyped).

### 2.10 Inline evaluation environment semantics

`p5_child_env.R` (full output §5.5), caller = `globalenv()` holding a 381 MB `big`:
1. Zero-copy reads: `mean(big)` in the agent env: heap 386.7 -> 387.7 MB (+1.0 MB); same `lobstr::obj_addr`; `tracemem()` reported 0 copies for `s <- sum(big); f <- function() length(big); f()`.
2. Writes local: `big <- big * 2; note <- ...` -> agent has `big,f,note,s`; caller's `big` unchanged at the same address; the local modified copy cost 381.5 MB.
3. Escape hatches, all MODIFIED the caller: (a) `counter <<- counter + 1`; (b) calling a caller-defined function that uses `<<-`; (c) `cfg$level <- 2` on an environment; (d) data.table `dt[, b := a * 10]`; (e) `assign(..., envir = globalenv())`; (f) `brand_new <<- 42` (name existing nowhere) is created in globalenv; (g) `runif()` changes globalenv's `.Random.seed`; (h) `rm(big)` in the agent only warns "object 'big' not found".
4. Guard: `counter <<- counter + 1` -> "error: cannot change value of locked binding for 'counter'"; `another_new <<- 1` not blocked but detected (`created = another_new`); `cfg$level <- 3` not blocked; bindings unlocked afterwards.
5. Export with conflict policy: `res` exported from agent 1; agent 2's `res` with `conflict = "error"` -> "export would overwrite `res` in the target environment"; with `"rename"` -> `res_a2`.

All VERIFIED. Evaluating in `new.env(parent = caller)` also means functions the agent defines have the overlay as enclosure and see caller objects, which is what agent-written helper functions need.

### 2.11 Interrupts and process cleanup

- `p6_session.R` + `p6_interrupt.R`: session owns 3 callr workers (`Sys.sleep(300)`), 2 CLI-like processes each with a grandchild, 4 long SSE streams, and waits in the reactor. Graceful case (SIGINT via `p$interrupt()`): "CLEANUP cancelled 4 transfers, kill_tree() killed pids [11866,11874,11876,11880,11921,11888,11920] in 190 ms", "INTERRUPT caught ... (class: interrupt/condition)", "RESULT gptr_aborted", session exited 0.41 s after the signal, nothing alive after 5 s. Hard case (SIGKILL; worker 3 started with `supervise = FALSE`): survivors `12509,12544,12560` = the unsupervised worker and both CLI grandchildren. The processx supervisor kills registered children when R dies but not their descendants. VERIFIED.
- processx docs (read locally): `cleanup_tree` "Whether to kill the process and its child process tree when the 'process' object is garbage collected"; `supervise` "the supervisor will ensure that the process is killed when the R process exits"; `kill_tree()` "works by marking the process with an environment variable, which is inherited in all child processes. This allows finding descendents, even if they are orphaned"; `interrupt()` "On Unix this is a 'SIGINT' signal ... On Windows, it is a CTRL+BREAK keypress"; `signal()` "On Windows only the 'SIGINT', 'SIGTERM' and 'SIGKILL' signals are interpreted ... The first three all kill the process". VERIFIED (docs).
- Interrupt latency (`p12_interrupt_latency.R`, SIGINT 1.5 s into each blocking call, fresh Rscript each): `Sys.sleep(30)` 0.007 s; `curl::multi_run(timeout = 30)` 0.000 s; `curl::curl_fetch_memory()` 0.001 s; httr2 blocking `resp_stream_sse()` 0.009 s; `processx::poll(list(p), 30000)` 0.202 s; callr `r_session$run(Sys.sleep(30))` 0.258 s; `m[]` on a 30 s mirai 0.292 s; pure-R loop 0.046 s; `later::run_now(30)` 0.000 s. All exited normally after the handler. VERIFIED (macOS).

### 2.12 Agent definition files

- Pi (source, VERIFIED): `agents.ts:11-19` `AgentConfig { name, description, tools?, model?, systemPrompt, source: "user"|"project", filePath }`; `agents.ts:34-39` raw frontmatter `{ name?, description?, tools?, model? }`; `parseToolList` (`agents.ts:53`) accepts `tools: read, bash` or `[read, bash]` and ignores anything else "where a single bad file must not take down every other agent". Sample `scout.md` frontmatter: `name: scout`, `description: Fast codebase recon ...`, `tools: read, grep, find, ls, bash`, `model: claude-haiku-4-5`. Directory scan is flat (report 06 §2.1.2).
- Claude Code (docs https://code.claude.com/docs/en/sub-agents, VERIFIED): required `name` (not starting with `-`, no `:`) and `description`; optional `tools`, `disallowedTools`, `model` (`sonnet`, `opus`, `haiku`, `fable`, full id, `inherit`), `permissionMode` (`default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan`, `manual`; the docs call `manual` an alias for `default`), `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory` (`user|project|local`), `background`, `omitClaudeMd`, `effort`, `isolation: worktree`, `color`, `initialPrompt`, `experimental`. Locations and precedence: managed > `--agents` JSON > `.claude/agents/` (walk up from cwd, recursive, closest wins) > `~/.claude/agents/` (recursive) > plugin `agents/`. `--agents` JSON: `{"name": {"description", "prompt", "tools", "model", ...}}`. Limits: nesting default 3 (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`), concurrency default 20 (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`), error text "Concurrent subagent limit reached". The spawning tool is named `Agent` (formerly `Task`).
- `p8_agent_files.R` parsed Pi's four agents plus a synthetic Claude Code agent in a subdirectory (`.claude/agents/review/stats.md`) and a gptr override; skipped `broken.md` ("unparseable frontmatter") and `noname.md` ("name and description must be strings"); mapped `[Read, Grep, Glob, Bash(Rscript *), mcp__github__search_code, NotebookEdit]` to `read,grep,find,r,mcp__github__search_code` with `NotebookEdit` reported unknown; `model: opus` kept; `maxTurns: 12` -> 12; extra fields `color,memory` preserved; the gptr `scout` overrode Pi's. VERIFIED.
- Bug class found while prototyping: `m$mode` on the YAML list partially matched `model`, so every Pi agent showed its model as its mode. Use `m[["field"]]` for all frontmatter access. VERIFIED.

### 2.13 Console progress for concurrent agents

- `cli::is_dynamic_tty()` rules (read locally): option `cli.dynamic`, env `R_CLI_DYNAMIC`, TRUE for terminals and for stdout/stderr "within RStudio, the macOS R app, or RKWard IDE", FALSE otherwise. VERIFIED (docs).
- `p9_progress.R`: one status line redrawn with `\r` (spinner, per-agent token count or running tool, `[done/total]`), throttled to 10 Hz, trimmed with `cli::ansi_strtrim()` to `cli::console_width()`, with permanent event lines ("code: tool r summary(fit)", "stats: done (412 tokens, 2 turns)", "biology: FAILED (HTTP 529 overloaded)") printed above it. Piped (non-dynamic) run printed only the three event lines; `R_CLI_DYNAMIC=true` produced the redraw frames shown in §5.11. VERIFIED. Multi-line in-place redraw (cursor-up ANSI) is not portable to RStudio's console, so one line is the portable design (LIKELY).

### 2.14 Prior art

- Pi subagent extension (`packages/coding-agent/examples/extensions/subagent/index.ts`, commit 1b34779): `MAX_PARALLEL_TASKS = 8` (line 33), `MAX_CONCURRENCY = 4` (34), `PER_TASK_OUTPUT_CAP = 50 * 1024` (36); `mapWithConcurrencyLimit` worker pool preserving order (219-237); child args start `["--mode", "json", "-p", "--no-session"]` (300); abort sends `SIGTERM` (413) then `SIGKILL` after 5000 ms (415), throws "Subagent was aborted" (424); "Too many parallel tasks (N). Max is 8." (610). VERIFIED. Caveat (verifier): line 415 is `if (!proc.killed) proc.kill("SIGKILL")`, and Node's `subprocess.killed` "indicates whether the child process successfully received a signal from `subprocess.kill()`" (not whether it exited), so after a delivered SIGTERM the SIGKILL fallback is skipped. gptr's escalation should test `p$is_alive()`, not "a signal was sent".
- Pi agent loop: `ToolExecutionMode = "sequential" | "parallel"` (`packages/agent/src/types.ts:47`), default "parallel" (`agent.ts:253`), per-tool `executionMode?: ToolExecutionMode` (`types.ts:496`), and one sequential tool forces the whole batch sequential (`agent-loop.ts:516-521`). VERIFIED.
- ellmer 0.4.0: `parallel_chat(chat, prompts, max_active = 10, rpm = 500, on_error = c("return", "continue", "stop"))` runs conversations in lock-step rounds via `req_perform_parallel()` with `req_throttle(capacity = rpm, fill_time_s = 60)`: all first turns in parallel, then tools, then all second turns. Wall time per round is the slowest member. Independent state machines (gptr's design) avoid that. VERIFIED (printed source).
- Report 06 (track 06) measured a callr sub-agent pool (6 tasks at concurrency 4 in ~2.0 s) and designed a JSONL process protocol; this report is consistent with it and supersedes its "fork" recommendation with the caveats in §2.8.

### 2.15 CRAN rules that bind this subsystem

- CRAN Repository Policy (https://cran.r-project.org/web/packages/policies.html): "If running a package uses multiple threads/cores it must never use more than two simultaneously"; "Checking the package should take as little CPU time as possible"; "Examples should run for no more than a few seconds each"; "Packages should not write in the user's home filespace ... nor anywhere else on the file system apart from the R session's temporary directory"; "Packages should not start external software (such as PDF viewers or browsers) during examples or tests unless that specific instance of the software is explicitly closed afterwards". VERIFIED.
- R Internals, Tools (https://rstudio.github.io/r-manuals/r-ints/Tools.html): `_R_CHECK_LIMIT_CORES_` "check the usage of too many cores in package parallel ... any other non-empty value gives an error when more than 2 children are spawned. Default: unset (but TRUE for CRAN submission checks)"; `_R_CHECK_CONNECTIONS_LEFT_OPEN_` "check for each example if connections are left open: if any are found, this is reported with a fatal error" (true for CRAN checks); `_R_CHECK_THINGS_IN_TEMP_DIR_`, `_R_CHECK_THINGS_IN_CHECK_DIR_`; `--as-cran` enables all four. VERIFIED.
- `parallelly::availableCores()` honours both: `_R_CHECK_LIMIT_CORES_=TRUE` -> 2; `options(mc.cores = 3)` -> 3 (min over sources; executed with `which = "all"`: system 8, /proc/self/status 8, mc.cores 3). VERIFIED.

---

## 3. Exact specifications

### 3.1 Signatures used (executed: `args()` on installed versions)

```
curl::new_pool(total_con = 100, host_con = 6, max_streams = 10, multiplex = TRUE)
curl::multi_add(handle, done = NULL, fail = NULL, data = NULL, pool = NULL)
curl::multi_run(timeout = Inf, poll = FALSE, pool = NULL)
curl::multi_fdset(pool = NULL)          # list(reads, writes, exceptions, timeout)
curl::multi_cancel(handle)
curl::multi_list(pool = NULL)
curl::handle_setopt(h, pipewait = 0L)   # libcurl CURLOPT_PIPEWAIT; also new_handle(pipewait = 0L)
processx::poll(processes, ms)           # processes and connections and curl_fds() objects, mixed
processx::curl_fds(fds)                 # fds = curl::multi_fdset(pool)
later::later_fd(func, readfds = integer(), writefds = integer(), exceptfds = integer(), timeout = Inf, loop = current_loop())
later::run_now(timeoutSecs = 0L, all = TRUE, loop = current_loop())
callr::r_bg(func, args = list(), libpath = .libPaths(), repos = default_repos(), stdout = "|", stderr = "|",
            poll_connection = TRUE, error = getOption("callr.error", "error"),
            cmdargs = c("--slave", "--no-save", "--no-restore"), system_profile = FALSE,
            user_profile = "project", env = rcmd_safe_env(), supervise = FALSE, package = FALSE, arch = "same", ...)
callr::r_session methods: attach, call, clone, close, debug, finalize, get_running_time, get_state, initialize,
                          poll_process, print, read, run, run_with_output, traceback
mirai::mirai(.expr, ..., .args = list(), .timeout = NULL, .compute = NULL)
mirai::mirai_map(.x, .f, ..., .args = list(), .promise = NULL, .compute = NULL)
mirai::everywhere(.expr, ..., .args = list(), .min = 1L, .compute = NULL)
mirai::stop_mirai(x)
mirai::daemons(n, url = NULL, remote = NULL, dispatcher = TRUE, ..., sync = FALSE, seed = NULL, serial = NULL,
               tls = NULL, pass = NULL, .compute = NULL)          # 2.6.1; 2.7.x adds memory = NULL
mori::share(x); mori::is_shared(x); mori::shared_name(x); mori::map_shared(name); mori::prune_shared()
parallel::mcparallel(expr, name, mc.set.seed = TRUE, silent = FALSE, mc.affinity = NULL, mc.interactive = FALSE, detached = FALSE)
parallel::mccollect(jobs, wait = TRUE, timeout = 0, intermediate = FALSE)
parallelly::availableCores(constraints = NULL, methods = ..., na.rm = TRUE, logical = ..., default = c(current = 1L),
                           which = c("min", "max", "all"), omit = ..., max = ...)
httr2::req_perform_connection(req, blocking = TRUE, verbosity = NULL, mock = getOption("httr2_mock", NULL))
httr2::resp_stream_sse(resp, max_size = Inf)   # NULL at end of stream or, when non-blocking, when no event is ready
httr2::req_perform_parallel(reqs, paths = NULL, on_error = c("stop", "return", "continue"), progress = TRUE, max_active = 10, mock = ...)
httr2::req_perform_promise(req, path = NULL, pool = NULL, verbosity = NULL, mock = ...)
```

### 3.2 Anthropic streaming event sequence (as emitted by the mock and consumed by the assembler)

```
event: message_start        data: {"type":"message_start","message":{"id":"msg_x","type":"message","role":"assistant","model":"mock-1","content":[],"stop_reason":null,"usage":{"input_tokens":100,"output_tokens":1}}}
event: content_block_start  data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}
event: content_block_delta  data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"x-first-1 "}}
event: content_block_stop   data: {"type":"content_block_stop","index":0}
event: content_block_start  data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_x","name":"r","input":{}}}
event: content_block_delta  data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"code\":\"m <- "}}
...                                                                         (3 fragments; concatenate, parse at content_block_stop)
event: content_block_stop   data: {"type":"content_block_stop","index":1}
event: message_delta        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":18}}
event: message_stop         data: {"type":"message_stop"}
```
Next request appends `{"role":"assistant","content":[...blocks...]}` and `{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_x","content":"...","is_error":false}]}`. (Full provider details belong to track 03.)

### 3.3 Claude Code agent file (reference format gptr reads)

```markdown
---
name: stats-reviewer                      # required; no ':' and not starting with '-'
description: Reviews statistical methodology. Use after model fitting.   # required
tools: [Read, Grep, Glob, Bash(Rscript *), mcp__github__search_code]    # or "Read, Grep"; omitted = defaults
disallowedTools: Write
model: opus                               # sonnet | opus | haiku | fable | <full id> | inherit
maxTurns: 12
permissionMode: plan                      # default|acceptEdits|auto|dontAsk|bypassPermissions|plan|manual
effort: high                              # low|medium|high|xhigh|max
skills: statistics, single-cell
mcpServers: [github]
color: blue                               # ignored by gptr, preserved in $extra
mode: inline                              # gptr extension (inline | worker | cli); other harnesses ignore unknown fields
---
You are a careful statistician. Check assumptions first.
```

Claude Code `--agents` JSON: `{"code-reviewer": {"description": "...", "prompt": "...", "tools": ["Read","Grep"], "model": "sonnet"}}`; all frontmatter fields allowed; `color` and `experimental` ignored.

### 3.4 CLI invocations for `mode = "cli"`

```
# Claude Code (subscription login; do NOT pass --bare, which forces ANTHROPIC_API_KEY)
claude -p --output-format stream-json --verbose [--include-partial-messages]
       --model <alias|id> --permission-mode <plan|acceptEdits|auto|dontAsk|manual>
       [--allowedTools "Read,Grep"] [--tools "..."] [--append-system-prompt <text>]
       [--agents <json>] [--mcp-config <file>] [--max-budget-usd <n>] [--no-session-persistence]
       < prompt.txt                                   # prompt on stdin (10 MB cap)
  stdout JSONL: {"type":"system","subtype":"init",...}, {"type":"assistant",...}, {"type":"user",...},
                {"type":"stream_event",...} (with --include-partial-messages), {"type":"system","subtype":"api_retry",...},
                last line {"type":"result","subtype":"success"|..., "is_error":bool, "result":"...", "session_id":"...",
                           "total_cost_usd":n, "usage":{...}, "num_turns":n, "duration_ms":n}
  cancel: SIGINT (ends the turn) -> grace -> kill_tree(); SIGTERM gives exit 143 and no result
# Codex (ChatGPT plan login)
codex exec --json -m <model> -s <read-only|workspace-write> -C <dir> --skip-git-repo-check --ephemeral
           [-o <last-message-file>] [--output-schema <file>] -     # "-" = read prompt from stdin
  stdout JSONL: thread.started{thread_id}, turn.started, item.started/item.updated/item.completed{item{id,type,text,...}},
                turn.completed{usage{input_tokens,cached_input_tokens,output_tokens,reasoning_output_tokens}}, turn.failed, error
```

### 3.5 Proposed model-facing tool `agent` (JSON Schema)

Superset of Pi's `subagent` parameters (report 06 §3.2) so models that learned Pi/Claude conventions transfer:

```json
{
  "name": "agent",
  "description": "Delegate work to one or more sub-agents. Each sub-agent has its own context, model and tools. Use `tasks` to run several at once (max 8, up to 4 concurrently by default) and `chain` to run steps in order, where {previous} is replaced by the previous step's output. Inline sub-agents can read the R objects named in `objects` directly from the session without copying.",
  "input_schema": {
    "type": "object",
    "properties": {
      "agent":   {"type": "string", "description": "Name of a defined agent (single mode). Omit for a general agent."},
      "task":    {"type": "string", "description": "Task for the agent (single mode)."},
      "tasks":   {"type": "array", "maxItems": 8, "description": "Tasks to run in parallel.",
                  "items": {"type": "object", "required": ["task"], "properties": {
                    "agent": {"type": "string"}, "task": {"type": "string"},
                    "model": {"type": "string", "description": "provider/model or alias; overrides the agent's model"},
                    "mode":  {"type": "string", "enum": ["inline", "worker", "cli"]}}}},
      "chain":   {"type": "array", "description": "Steps to run in order; {previous} = prior output.",
                  "items": {"type": "object", "required": ["task"], "properties": {
                    "agent": {"type": "string"}, "task": {"type": "string"}, "model": {"type": "string"}}}},
      "model":   {"type": "string"},
      "mode":    {"type": "string", "enum": ["inline", "worker", "cli"], "default": "inline"},
      "objects": {"type": "array", "items": {"type": "string"},
                  "description": "Names of R objects the sub-agents need. inline: read in place; worker: copied (or shared memory)."},
      "export":  {"type": "array", "items": {"type": "string"},
                  "description": "Names of objects the sub-agents should create and return into the session."}
    }
  }
}
```

Tool result text: single -> final text; parallel -> `Parallel: X/N succeeded` + one `### [agent] completed|failed (<status>)` section per task, each capped at 50 KB with `[Output truncated: N bytes omitted]`; chain -> last output or `Chain stopped at step N (<agent>): <error>` (Pi's wording). The structured `details` carry per-task `gptr_result`s and summed usage.

### 3.6 Worker (process) JSONL protocol (child stdout -> parent, parent -> child stdin)

Child -> parent, one JSON object per line, UTF-8 (`writeLines(enc2utf8(json), stdout(), useBytes = TRUE)`, `flush(stdout())`), non-JSON lines ignored:
```
{"type":"agent_start","agent":"stats","pid":1234,"model":"anthropic/claude-..."}
{"type":"text_delta","text":"..."}                          # optional, throttled
{"type":"tool_start","tool":"r","id":"toolu_1","summary":"summary(fit)"}
{"type":"tool_end","id":"toolu_1","is_error":false,"bytes":532}
{"type":"message_end","role":"assistant","usage":{"input":1200,"output":300,"cache_read":800,"cache_write":0,"cost":0.0123}}
{"type":"ask","id":"q1","question":"Which cohort?","choices":["A","B"]}
{"type":"permission_request","id":"p1","tool":"write","summary":"write analysis.R"}
{"type":"result","status":"ok","text":"...","usage":{...},"turns":2}
```
Parent -> child: `{"type":"answer","id":"q1","text":"A"}`, `{"type":"permission","id":"p1","allow":true}`, `{"type":"cancel"}`. The R value returned by the worker function comes back through callr's result file (`p$get_result()`), not the JSONL stream.

### 3.7 Constants and limits (proposed defaults, with provenance)

| Setting (option) | Default | Source / reason |
|---|---|---|
| `gptr.max_tasks` per `agent` tool call | 8 | Pi `MAX_PARALLEL_TASKS` |
| `gptr.max_active` inline agents at once | 8 | HTTP concurrency; provider limits dominate |
| `gptr.max_active_cli` | 4 | Pi `MAX_CONCURRENCY`; each CLI is a Node process |
| `gptr.max_workers` | `min(4, availableCores(omit = 1))`, and ≤ 2 when `_R_CHECK_LIMIT_CORES_` is set (verified: with `_R_CHECK_LIMIT_CORES_=TRUE`, `availableCores()` = 2 and `availableCores(omit = 1)` = 1) | CRAN policy, parallelly |
| `gptr.subagent_depth` | 1 (sub-agents get no `agent` tool) | Claude Code default 3; start conservative |
| per-task output returned to the parent model | 50 KB | Pi `PER_TASK_OUTPUT_CAP` |
| abort grace before kill | SIGINT, then `kill_tree()` after 5 s if still alive | Pi SIGTERM→SIGKILL 5 s (intent; its `!proc.killed` guard skips the SIGKILL, §2.14); Claude Code wants SIGINT |
| status redraw | ≤ 10 Hz | p9 |
| worker start-up | 0.25-0.45 s callr; warm run 30-60 ms | p4 |
| reactor poll slice | ≤ 100-250 ms | responsiveness; Ctrl-C lands ≤ 0.2 s inside processx::poll |

---

## 4. Recommended design for gptr

### 4.1 D-13 decision

**Adopt a gptr-owned reactor built on `curl` multi handles.** Rationale from measurements: it is the lowest-level API that streams with push callbacks, supports any number of concurrent transfers in one pool, is interruptible (< 1 ms), has no busy-waiting, integrates with child processes through `processx::curl_fds()`, and adds no dependency (curl is already a hard dependency of httr2). httr2 remains useful for one-off non-streaming calls and OAuth (tracks 03/07/08); if gptr builds requests with httr2 for other reasons, it can still hand the final URL, headers and body to curl for the streaming path. promises/later are optional layers (background mode, Shiny), not the engine. coro is not used.

Mandatory transport settings: `pipewait = 0L` on every handle (§2.2); `new_pool(total_con = 100, host_con = 100)`; per-transfer `low_speed_limit`/`low_speed_time` stall detection; `accept: text/event-stream`; `multi_cancel()` on abort.

### 4.2 Architecture

```
gptr() / gptr_parallel() / agent tool / background job
        │  creates run specs
        ▼
  gptr_reactor (one per top-level call; an environment)
    pool        curl multi pool (pipewait = 0 on handles)
    agents      list of gptr_agent_run (environments = state machines)
    procs       worker / cli processx objects
    tool_queue  FIFO of pending tool calls (R-eval tools are sequential)
    timers      retry/backoff wake-ups (429, 529, 5xx with Retry-After)
    ui          status renderer (single line) + event log
    loop:
      start queued runs while slots free (global and per-provider semaphores)
      if tool_queue: run ONE tool (overlay env, binding guard, per-agent RNG, capture output,
                     setTimeLimit), append result, drain network (multi_run(timeout = 0)), continue
      else: processx::poll(c(curl_fds(multi_fdset(pool)), live procs), ms = min(next timer, 100-250))
            multi_run(timeout = 0); read JSONL from ready procs; fire due timers
      until every run is done/error/aborted
    on.exit: multi_cancel all; interrupt() procs; kill_tree() after grace; mark runs aborted
```

Agent-run state machine (environment, S3 class `gptr_agent_run`): `queued -> requesting -> streaming -> (tools_pending -> tool_running)* -> done | error | aborted`, plus `waiting_children` (nested `agent` tool) and `waiting_user` (ask-user/permission requests are queued and asked one at a time by the reactor while other agents continue, REQ-36/37). Fields: `id`, `name`, `agent` (definition), `model`, `mode`, `messages`, `env` (overlay), `rng_seed`, `usage`, `turns`, `text`, `value`, `exports`, `status`, `error`, `started`, `finished`, `parent_id`, `depth`.

Tool execution policy (mirrors Pi's per-tool `executionMode`): tools declare `sequential` (anything evaluating R or touching files: `r`, `write`, `edit`) or `concurrent` (pure I/O: web fetch, MCP-over-HTTP, nested `agent`). Sequential tools go through the global FIFO; concurrent tools are themselves reactor transfers.

### 4.3 Public R API (S-1: `gptr()` is the gateway; D-28: helpers carry the `gptr_` prefix)

```r
# 1) Several agents on one prompt (north-star example 6). Inside `agents =`, `agent()` is an alias of
#    gptr_agent() (evaluated with a data mask), so the north-star spelling works without exporting agent().
reviews <- gptr("Review analysis.R for statistical errors.",
                agents = list(stats   = agent(model = opus, skills = statistics),
                              code    = agent(model = codex, mode = "cli"),
                              biology = agent(model = gemini, skills = single_cell)))
reviews$stats                     # gptr_results is a named list of gptr_result

# 2) Fan-out over a list (north-star): gptr(prompt, <list context>, parallel = n)  == gptr_map()
summaries <- gptr("Summarise this cohort", cohorts, parallel = 4)
gptr_map(.x, prompt, ..., model = NULL, agent = NULL, max_active = 4, mode = "inline",
         simplify = FALSE, .progress = interactive())

# 3) Any gptr() calls, concurrently (deferred evaluation)
gptr_parallel(..., .list = NULL, max_active = getOption("gptr.max_active", 8),
              on_error = c("return", "stop"), timeout = Inf, .progress = interactive())
#   gptr_parallel(plan = gptr("Plan the analysis", model = opus),
#                 lit  = gptr("Summarise the literature on X", model = gemini))
#   Each argument is a promise; gptr_parallel forces them with a dynamic flag set, under which gptr()
#   returns an unstarted `gptr_pending` spec instead of running. The reactor then runs all specs together.

# 4) Agent definitions
gptr_agent(name = NULL, model = NULL, tools = NULL, skills = NULL, system = NULL,
           mode = c("inline", "worker", "cli"), envir = NULL, objects = NULL, export = NULL,
           max_turns = NULL, permission = NULL, file = NULL, ...)
#   gptr_agent("stats-reviewer") loads a definition file by name (§4.10).
gptr_agents(scope = c("all", "project", "user"))        # list discovered definitions

# 5) Chains are pipes (REQ-18/35): model changes mid-chain = cross-LLM hand-off (track 02/03)
gptr("Plan the analysis", model = opus) |> gptr("Implement the plan", model = codex) |>
  gptr("Review the implementation", model = gemini)

# 6) Cross-LLM helpers (REQ-34), thin wrappers over gptr_parallel() and control flow
gptr_panel(prompt, ..., models, judge = NULL, rounds = 1)       # same question to N models; optional synthesis
gptr_debate(prompt, ..., models, rounds = 2, judge = NULL)      # each round sees the others' previous answers
gptr_review(task, implementer, reviewer, max_rounds = 3,
            approved = function(review) gptr("Does this review approve the work?", review, model = jev))

# 7) Background jobs (optional, needs later): returns immediately; progresses while the console is idle
job <- gptr("Profile every column of big_df", big_df, background = TRUE)
gptr_wait(job, timeout = Inf); gptr_cancel(job); gptr_jobs()

# 8) Accounting
gptr_usage(x)        # sums usage over a gptr_result / gptr_results / session, incl. sub-agents
```

Result objects:
```r
# gptr_result (list, S3): text, value, model, agent, mode, status ("ok"|"error"|"aborted"|"timeout"),
#   error (condition or NULL), usage = list(input, output, cache_read, cache_write, cost, turns,
#   by_model = data.frame), messages, exports (character: names written into the target env),
#   started, finished, duration, session (handle for continuation), children (gptr_results or NULL)
# gptr_results (named list of gptr_result, S3): print() = one row per agent (name, model, status,
#   tokens, cost, seconds, first line of text); summary(); as.data.frame(); `$`/`[[` by name;
#   usage attribute = sum over members
```

Mapping of the task's suggested names to this API: `subagent(prompt, model, tools, envir, mode)` = `gptr(prompt, model =, tools =, envir =, mode =)` or `gptr(prompt, agents = list(x = gptr_agent(...)))`; `agents(...)` = `gptr_parallel(...)`; `agent_map` = `gptr_map()`; chain = the native pipe; panel/debate/review = `gptr_panel()`, `gptr_debate()`, `gptr_review()`.

Mode selection (`mode = "auto"` default; UNCERTAIN/inconsistent: the `gptr_agent()` signature above defaults to `"inline"` and has no `"auto"`, and the §3.5 tool schema also defaults to `"inline"`; the implementation plan must pick one and update the other two): `inline` unless the agent file or call says otherwise, or the model is a CLI-only provider (`codex`, `claude-code` plan providers -> `cli`). `worker` is chosen explicitly (heavy R compute in parallel, isolation). `fork` exists only as an explicit Unix-terminal opt-in.

### 4.4 Modes in detail

| | inline | worker | cli |
|---|---|---|---|
| Process | same R process | `callr::r_bg()` (or warm `r_session` pool) | `processx::process$new(Sys.which("claude"/"codex"), ...)` |
| Sees live objects | yes, zero-copy via overlay env | only `objects =` (serialized, or `mori::share()` when installed and size ≥ threshold, e.g. 50 MB, atomic/list/data.frame; S4 via slot sharing) | no (future: via gptr MCP bridge) |
| CPU parallelism | no (tools serialized) | yes | yes |
| Start-up | ~0 | 0.25-0.45 s (callr) | CLI start-up (not measured) |
| Events to parent | in-process | JSONL on stdout (§3.6) | CLI's JSONL |
| Ask/permission | reactor queue | JSONL request + stdin answer | CLI's own modes (`--permission-mode`, `-s`) |
| Cancellation | `multi_cancel()` | `interrupt()` then `kill_tree()` | `interrupt()` (SIGINT/CTRL+BREAK) then `kill_tree()` |
| Credentials | in-process | inherited env vars (never in args) | CLI's own login |
| Required spawn options | — | `supervise = TRUE`, `cleanup_tree = TRUE`, `user_profile = FALSE`, `system_profile = FALSE`, `libpath = .libPaths()`, env `GPTR_SUBAGENT_DEPTH` | `supervise = TRUE`, `cleanup_tree = TRUE`, `stdin = <prompt file>`, `stdout = "|"`, `stderr = "|"` |

mirai as an alternative worker backend: good for many short compute tasks (warm round trip < 1 ms, `mirai_map`), but no built-in event stream from a running task, a library-path trap at start-up, and slower large by-value transfers in 2.6.1. Recommend `Suggests: mirai` behind `mode = "worker", backend = "mirai"` for data-parallel helpers (e.g. `gptr_map()` over heavy R work), with callr as the default worker backend.

### 4.5 Environment policy for inline sub-agents

1. **Overlay**: each inline agent evaluates in `new.env(parent = envir)` (envir = caller's frame, D-04). Reads fall through with zero copy; assignments stay in the overlay; copy-on-modify makes a private copy only of what the agent modifies.
2. **Guard** (default on for inline sub-agents, off for the top-level agent unless `permission` says so): during each R-tool evaluation lock every not-already-locked binding of `envir` (box immediate bindings first), unlock in `on.exit`; diff names before/after to detect bindings created by `<<-`/`assign()` and move them into the overlay (or report them). Cost ~10-15 µs per binding. Document that environments, R6 objects, Seurat's internal environments and data.table `:=`/`set*()` can still be mutated in place; the static risk classifier (D-11) should flag `<<-`, `assign(`, `:=`, `set(`, `setattr(`, `setDT(` in sub-agent code.
3. **Export**: results reach the caller only by explicit export: the agent's final `value`, names in `export =`, or the model's `export` tool parameter. Conflict policy `conflict = c("error", "rename", "overwrite")`; default `"error"` for parallel runs, `"overwrite"` for a single sequential sub-agent. Exports happen after all parallel siblings finish, in task order, so results are deterministic.
4. **Shared mode**: `envir_mode = "shared"` lets a single inline sub-agent write directly into `envir` (like the parent agent); refused for parallel runs.
5. **RNG**: every agent run gets its own L'Ecuyer-CMRG stream (`parallel::nextRNGStream()` from a run seed, default from the session seed), swapped in and out around each tool evaluation (§5.12). Agents' results are reproducible regardless of interleaving; the user's RNG stream is untouched.
6. **Other process-global state** (options, working directory, env vars, attached packages, sinks, graphics devices) is shared; the R tool should snapshot and restore `options()`, `getwd()` and the sink stack around each call, and `library()` calls are allowed but reported.

### 4.6 Concurrency limits and rate limits

- Global semaphores per mode (§3.7) and per provider (`options(gptr.provider_concurrency = list(anthropic = 8, openai = 8, ollama = 1))`; local Ollama processes a limited number of requests in parallel by default, exact default UNCERTAIN).
- Honour HTTP 429/529 with `retry-after` via reactor timers, and optional client-side token-bucket throttling per provider (ellmer uses `req_throttle(capacity = rpm, fill_time_s = 60)`).
- Worker count: `min(getOption("gptr.max_workers", 4), parallelly::availableCores(omit = 1))`, hard cap 2 when `Sys.getenv("_R_CHECK_LIMIT_CORES_")` is non-empty and not "false".

### 4.7 Cancellation and interrupts (REQ-38)

- All cleanup lives in `on.exit()` of the reactor: `multi_cancel()` every handle, `p$interrupt()` every process, wait up to 5 s with `processx::poll()`, then `p$kill_tree()`, mark unfinished runs `aborted`, keep partial transcripts.
- The reactor catches the `interrupt` condition only to finish cleanup and record partial results (`gptr_last()`), then **re-signals** it, so that `for (t in tasks) gptr(t)` stops on Ctrl-C (catching and returning would let the loop continue). In the interactive console session (`gptr()` with no prompt) the interrupt returns to the gptr prompt (D-26).
- All children: `supervise = TRUE, cleanup_tree = TRUE`. For crash recovery, record the processx tree marker of each spawned child in a per-session file under `tools::R_user_dir("gptr", "cache")`; on the next start, `ps::ps_find_tree()`-style sweeps can kill orphaned grandchildren left by a hard crash (§2.11 showed grandchildren survive SIGKILL). UNCERTAIN (not prototyped).
- Per-tool time limit: `setTimeLimit(elapsed = t, transient = TRUE)` around R-tool evaluation (not prototyped here).

### 4.8 Progress display

Single status line via the renderer in §5.11: `[done/total] name spinner N tok | name running r: summary(fit) | name done`, redrawn ≤ 10 Hz only when `cli::is_dynamic_tty()`, permanent event lines above it for tool calls, completions and failures; plain event lines only in knitr/Rscript/Jupyter. The reactor calls `ui$update()` from the loop and `ui$event()` from state transitions.

### 4.9 Exposure to the model

- Model-visible tool `agent` (D-03 on-request tool), schema §3.5, registered when `agents`/`subagents` are enabled or an agent file set exists; not given to sub-agents unless depth allows.
- In R code (REQ-35), the model and the user call the same functions: `gptr()`, `gptr_parallel()`, `gptr_map()`, `gptr_panel()`. Agent-written orchestration is then an ordinary R script in the history document.
- System-prompt snippet lists available agents: `name: description (model, mode)`, like Claude Code, with a size budget (Claude Code does not hard-cap: when all custom agents' descriptions together exceed 15,000 tokens it shows a startup warning and still loads every agent).

### 4.10 Agent definition files

- Directories, low → high precedence: `~/.pi/agent/agents/` (flat), `~/.claude/agents/` (recursive), `tools::R_user_dir("gptr", "config")/agents` (recursive), then project `.pi/agents/`, `.claude/agents/`, `.gptr/agents/` (each the nearest found walking up from the working directory). Later wins by `name`.
- Parser: YAML frontmatter with `yaml::yaml.load()`, exact `[[` field access, skip (never error) files with unparseable frontmatter or non-string `name`/`description`, keep unknown fields in `$extra`, map tool names (`Read→read`, `Write→write`, `Edit|MultiEdit→edit`, `Grep→grep`, `Glob|find→find`, `LS→ls`, `Bash|PowerShell→r` (S-4), `Agent|Task→agent`, `AskUserQuestion→ask`, `mcp__*` unchanged), report unknown tools, `model: inherit` → NULL.
- Project agents are repository-controlled prompts: as in Pi, ask for confirmation before running project agents the first time (trust store under `R_user_dir`), unless running non-interactively with an explicit option.

### 4.11 Usage aggregation

Every `gptr_result` carries usage; a parent's session totals include all children (Pi's example does not, report 06 §2.1.5). CLI agents: Claude `result.usage` + `total_cost_usd`; Codex `turn.completed.usage` (no cost; compute from the model catalog). Workers: JSONL `message_end.usage`.

### 4.12 Package choices

| Package | Role | Recommendation |
|---|---|---|
| curl | reactor transport (multi handles, fdset) | **Imports** (already required by httr2; gptr calls it directly) |
| processx | child processes, `poll()`, `curl_fds()`, `kill_tree()`, supervisor | **Imports** (D-20 already) |
| callr | worker mode (`r_bg`, `r_session`) | **Imports** (adds R6 + processx, both already present, plus `otel` (>= 0.2.0) since callr 3.8.0; otel has no hard dependencies) |
| jsonlite, cli | JSON, UI | **Imports** (D-20) |
| yaml | agent/skill frontmatter | **Imports** (shared decision with skills track) |
| ps | pid checks, orphan sweep | comes with processx (processx Imports ps) |
| later | background jobs at the console | **Suggests** |
| promises | Shiny chat/artifact integration | **Suggests** |
| mirai (+nanonext) | optional worker backend for data-parallel helpers | **Suggests** |
| mori | shared-memory transport for large objects to workers | **Suggests** (needs compilation; the CRAN page lists 0.2.2 binaries for Windows r-devel/r-release/r-oldrel and macOS r-release/r-oldrel, arm64 and x86_64; only the frozen R 4.4 repository lacks one) |
| parallelly | `availableCores()`, `supportsMulticore()` | **Suggests** (or a 10-line internal equivalent honouring `mc.cores` and `_R_CHECK_LIMIT_CORES_`) |
| coro, future, crew | — | not used |
| webfakes | alternative mock server in tests | Suggests only if the base-R mock is not adopted |

---

## 5. Verified prototypes

All files are in `scratchpad/work/15/` (paths below are relative to it). Every listing is the exact code that produced the output shown. Scripts that need the private library were run with `R_LIBS=<scratchpad>/rlib Rscript --vanilla <file>`; others with `Rscript --vanilla <file>`.

### 5.0 Package versions on CRAN versus installed (executed: `install_mori.R`)

```
mori         binary NA       source 0.2.2    | Imports: NA
mirai        binary 2.6.1    source 2.7.3    | Imports: nanonext (>= 1.10.3)
nanonext     binary 1.8.1    source 1.10.3
crew         binary 1.3.0    source 1.3.3    | Imports: cli (>= 3.1.0), collections (>= 0.3.9), data.table, later, mirai (>= 2.7.0), nanonext (>= 1.9.0), processx, promises, ps, R6, rlang, stats, tibble, tidyselect, tools, utils
parallelly   binary 1.46.1   source 1.48.0
callr        binary 3.7.6    source 3.8.0    | Imports: otel (>= 0.2.0), processx (>= 3.6.1), R6, utils
processx     binary 3.8.6    source 3.9.0    | Imports: ps (>= 1.9.3), R6, utils
later        binary 1.4.8    source 1.4.8    | Imports: Rcpp (>= 1.0.10), rlang
promises     binary 1.5.0    source 1.5.0
coro         binary 1.1.0    source 1.1.0    | Imports: rlang (>= 0.4.12)
httr2        binary 1.2.2    source 1.3.0    | Imports: cli (>= 3.0.0), curl (>= 6.4.0), glue, lifecycle, magrittr, openssl, R6, rlang (>= 1.3.0), vctrs (>= 0.6.3), withr
curl         binary 7.0.0    source 8.0.0
future       binary 1.70.0   source 1.76.0
webfakes     binary 1.4.0    source 1.5.0
```
(`binary` = frozen R 4.4 macOS binaries; curl 8.1.0 appears in the GitHub NEWS.) mori was installed from source into the private library: `install.packages("mori", lib = lib, type = "source")` -> `* DONE (mori)`, `[1] '0.2.2'`.

### 5.1 Mock servers

`p0_httpuv_nostream.R` (httpuv cannot stream):
```r
srv <- callr::r_bg(function(port) {
  app <- list(call = function(req) {
    promises::promise(function(resolve, reject) {
      toks <- character(); i <- 0L
      step <- function() {
        i <<- i + 1L
        toks <<- c(toks, sprintf("event: token\ndata: {\"i\":%d}\n\n", i))
        if (i < 5L) later::later(step, 0.3) else
          resolve(list(status = 200L, headers = list("Content-Type" = "text/event-stream"),
                       body = paste(toks, collapse = "")))
      }
      later::later(step, 0.3)
    })
  })
  s <- httpuv::startServer("127.0.0.1", port, app)
  repeat httpuv::service(100)
}, args = list(port = 8765L))
Sys.sleep(1.5)
t0 <- Sys.time(); arrivals <- character()
h <- curl::new_handle()
curl::curl_fetch_stream("http://127.0.0.1:8765/sse", function(x) {
  n <- lengths(regmatches(rawToChar(x), gregexpr("event: token", rawToChar(x))))
  arrivals <<- c(arrivals, sprintf("%.2fs: chunk of %d bytes holding %d token events", as.numeric(Sys.time() - t0), length(x), n))
}, handle = h)
cat("httpuv", as.character(packageVersion("httpuv")), "arrivals:\n"); cat(" ", arrivals, sep = "\n  ")
srv$kill()
```
Output: `httpuv 1.6.17 arrivals:` / `1.53s: chunk of 140 bytes holding 5 token events`.

`mock_sse_base.R` (the zero-dependency streaming mock used by every prototype below):
```r
# mock_sse_base.R -- a zero-dependency mock "LLM provider" that streams Server-Sent Events,
# written in base R (serverSocket + socketSelect, R >= 4.0). One R process multiplexes all
# client connections, so N streams are served concurrently even though R is single-threaded.
# (httpuv cannot do this: its response body is one string/raw vector sent at once; see p0_httpuv_nostream.R.)
#
# Endpoints
#   GET  /ping                                -> "pong"
#   GET  /sse?id=A&n=8&delay=0.15&first=0     -> n "token" events, one every `delay` s, then "done"
#   POST /v1/messages                         -> Anthropic-shaped SSE. Request JSON may carry
#        "mock": {"name":..., "tokens":5, "delay":0.1, "first":0, "tool_code":"<R code>"}
#        If the last message is a user message whose first content block is a tool_result, the reply
#        is text only (end_turn). Otherwise, if mock.tool_code is set, the reply ends with a tool_use
#        block (tool "r", input {"code": tool_code}) split into 3 input_json_delta fragments.
#
# start_mock_sse() launches the server in a callr background process and returns list(url, proc).

mock_sse_serve <- function(port) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
  now <- function() as.numeric(Sys.time())
  json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
  sse <- function(event, data) paste0("event: ", event, "\ndata: ", if (is.character(data)) data else json(data), "\n\n")
  parse_query <- function(q) {
    if (!nzchar(q)) return(list())
    kv <- strsplit(strsplit(q, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
    stats::setNames(lapply(kv, function(p) utils::URLdecode(p[2] %||% "")), vapply(kv, `[`, "", 1))
  }
  anthropic_events <- function(body) {
    plan <- body$mock %||% list()
    msgs <- body$messages
    last <- msgs[[length(msgs)]]
    is_tool_result <- is.list(last$content) && length(last$content) > 0 &&
      identical(last$content[[1]]$type, "tool_result")
    name <- plan$name %||% "agent"; ntok <- as.integer(plan$tokens %||% 5L)
    ev <- character()
    add <- function(e, d) ev <<- c(ev, sse(e, d))
    add("message_start", list(type = "message_start", message = list(id = paste0("msg_", name),
      type = "message", role = "assistant", model = body$model %||% "mock-1", content = list(),
      stop_reason = NULL, usage = list(input_tokens = 100L, output_tokens = 1L))))
    add("content_block_start", list(type = "content_block_start", index = 0L,
      content_block = list(type = "text", text = "")))
    phase <- if (is_tool_result) "final" else "first"
    for (i in seq_len(ntok)) add("content_block_delta", list(type = "content_block_delta", index = 0L,
      delta = list(type = "text_delta", text = sprintf("%s-%s-%d ", name, phase, i))))
    add("content_block_stop", list(type = "content_block_stop", index = 0L))
    stop_reason <- "end_turn"
    if (!is_tool_result && !is.null(plan$tool_code)) {
      stop_reason <- "tool_use"
      add("content_block_start", list(type = "content_block_start", index = 1L,
        content_block = list(type = "tool_use", id = paste0("toolu_", name), name = "r",
                             input = structure(list(), names = character()))))
      js <- json(list(code = plan$tool_code))
      cuts <- unique(c(0L, floor(nchar(js) / 3), floor(2 * nchar(js) / 3), nchar(js)))
      for (k in seq_len(length(cuts) - 1L)) add("content_block_delta", list(type = "content_block_delta",
        index = 1L, delta = list(type = "input_json_delta", partial_json = substr(js, cuts[k] + 1L, cuts[k + 1L]))))
      add("content_block_stop", list(type = "content_block_stop", index = 1L))
    }
    add("message_delta", list(type = "message_delta", delta = list(stop_reason = stop_reason),
      usage = list(output_tokens = ntok + 10L)))
    add("message_stop", list(type = "message_stop"))
    list(events = ev, delay = as.numeric(plan$delay %||% 0.1), first = as.numeric(plan$first %||% 0))
  }
  srv <- serverSocket(port)
  clients <- list(); next_id <- 0L
  header <- function(ctype) paste0("HTTP/1.1 200 OK\r\nContent-Type: ", ctype,
    "\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n")
  respond_plain <- function(cl, text) {
    writeBin(charToRaw(paste0("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: ",
      nchar(text, "bytes"), "\r\nConnection: close\r\n\r\n", text)), cl$con)
    cl$closing <- TRUE; cl
  }
  start_request <- function(cl) {
    head_end <- grepRaw("\r\n\r\n", cl$buf, fixed = TRUE)
    if (!length(head_end)) return(cl)
    head <- strsplit(rawToChar(cl$buf[seq_len(head_end - 1L)]), "\r\n", fixed = TRUE)[[1]]
    rl <- strsplit(head[1], " ", fixed = TRUE)[[1]]
    hdr <- tolower(sub(":.*$", "", head[-1])); val <- trimws(sub("^[^:]*:", "", head[-1]))
    clen <- as.integer(val[hdr == "content-length"][1] %||% 0L); if (is.na(clen)) clen <- 0L
    body_start <- head_end + 4L
    if (length(cl$buf) - body_start + 1L < clen) return(cl)          # wait for the full body
    body <- if (clen > 0) rawToChar(cl$buf[body_start:(body_start + clen - 1L)]) else ""
    path <- sub("\\?.*$", "", rl[2]); q <- parse_query(if (grepl("?", rl[2], fixed = TRUE)) sub("^[^?]*\\?", "", rl[2]) else "")
    cl$state <- "stream"
    if (path == "/ping") return(respond_plain(cl, "pong"))
    if (path == "/sse") {
      id <- q$id %||% "X"; n <- as.integer(q$n %||% 5L); d <- as.numeric(q$delay %||% 0.1)
      ev <- c(vapply(seq_len(n), function(i) sse("token", list(id = id, i = i, t = paste0(id, i, " "))), ""),
              sse("done", "[DONE]"))
      cl$events <- ev; cl$delay <- d; cl$due <- now() + as.numeric(q$first %||% 0) + d
    } else if (path == "/v1/messages") {
      p <- anthropic_events(jsonlite::fromJSON(body, simplifyVector = FALSE))
      cl$events <- p$events; cl$delay <- p$delay; cl$due <- now() + p$first + p$delay
    } else return(respond_plain(cl, "not found"))
    writeBin(charToRaw(paste0(header("text/event-stream"), ": stream open\n\n")), cl$con)
    cl$i <- 0L; cl
  }
  repeat {
    t <- now()
    dues <- vapply(clients, function(cl) if (identical(cl$state, "stream") && !isTRUE(cl$closing)) cl$due else Inf, 0)
    wait <- max(0, min(c(0.25, dues - t)))
    reading <- Filter(function(cl) identical(cl$state, "read"), clients)
    ready <- socketSelect(c(list(srv), lapply(reading, `[[`, "con")), timeout = wait)
    if (ready[1]) {
      con <- socketAccept(srv, blocking = FALSE, open = "r+b")
      next_id <- next_id + 1L
      clients[[as.character(next_id)]] <- list(con = con, buf = raw(0), state = "read")
    }
    for (k in names(reading)[ready[-1]]) {
      cl <- clients[[k]]
      chunk <- readBin(cl$con, "raw", 65536L)
      cl$buf <- c(cl$buf, chunk)
      clients[[k]] <- start_request(cl)
    }
    t <- now()
    for (k in names(clients)) {
      cl <- clients[[k]]
      if (identical(cl$state, "stream") && !isTRUE(cl$closing) && t >= cl$due) {
        cl$i <- cl$i + 1L
        ok <- tryCatch({ writeBin(charToRaw(cl$events[cl$i]), cl$con); flush(cl$con); TRUE }, error = function(e) FALSE)
        if (!ok || cl$i >= length(cl$events)) cl$closing <- TRUE else cl$due <- cl$due + cl$delay
        clients[[k]] <- cl
      }
      if (isTRUE(clients[[k]]$closing)) { close(clients[[k]]$con); clients[[k]] <- NULL }
    }
  }
}

start_mock_sse <- function(port = NULL) {
  if (is.null(port)) port <- as.integer(stats::runif(1, 20000, 40000))
  proc <- callr::r_bg(mock_sse_serve, args = list(port = port), supervise = TRUE)
  url <- sprintf("http://127.0.0.1:%d", port)
  for (i in 1:100) {                       # wait until it answers /ping
    ok <- tryCatch(rawToChar(curl::curl_fetch_memory(paste0(url, "/ping"))$content) == "pong", error = function(e) FALSE)
    if (ok) break
    Sys.sleep(0.05)
  }
  if (!proc$is_alive()) stop("mock server died: ", paste(proc$read_all_error_lines(), collapse = "\n"))
  list(url = url, proc = proc, stop = function() proc$kill())
}
```

`sse.R` (previous researcher's incremental SSE parser, kept unchanged; used by p1, p3, p10):
```r
# sse.R -- incremental Server-Sent-Events parser over raw chunks (base R only).
# feed(bytes) returns a list of complete events: list(event = chr, data = chr, id = chr|NULL, retry = int|NULL)
# Handles LF, CRLF and CR line ends, chunks that split a line or a multi-byte character, comments,
# multi-line data, and events whose data is empty (kept, unlike httr2::resp_stream_sse()).
sse_parser <- function() {
  buf <- raw(0)
  cur <- list(event = "message", data = character(), id = NULL, retry = NULL, has_field = FALSE)
  reset <- function() cur <<- list(event = "message", data = character(), id = NULL, retry = NULL, has_field = FALSE)
  take_lines <- function(final = FALSE) {
    n <- length(buf)
    if (!n) return(character())
    lf <- which(buf == as.raw(0x0a)); cr <- which(buf == as.raw(0x0d))
    # a CR directly followed by LF is one terminator; a CR at the very end may be half of a CRLF
    cr_solo <- cr[!( (cr + 1L) %in% lf )]
    if (!final && length(cr_solo) && cr_solo[length(cr_solo)] == n) cr_solo <- cr_solo[-length(cr_solo)]
    ends <- sort(c(lf, cr_solo))
    if (!length(ends)) return(character())
    starts <- c(1L, ends[-length(ends)] + 1L)
    out <- character(length(ends))
    for (i in seq_along(ends)) {
      e <- ends[i] - 1L
      if (e >= starts[i] && buf[e] == as.raw(0x0d) && buf[ends[i]] == as.raw(0x0a)) e <- e - 1L
      out[i] <- if (e >= starts[i]) rawToChar(buf[starts[i]:e]) else ""
    }
    buf <<- if (ends[length(ends)] < n) buf[(ends[length(ends)] + 1L):n] else raw(0)
    Encoding(out) <- "UTF-8"
    out
  }
  feed <- function(bytes, final = FALSE) {
    if (length(bytes)) buf <<- c(buf, bytes)
    lines <- take_lines(final)
    events <- list()
    for (ln in lines) {
      if (!nzchar(ln)) {                                   # blank line: dispatch
        if (cur$has_field) {
          events[[length(events) + 1L]] <- list(event = cur$event, data = paste(cur$data, collapse = "\n"),
                                                id = cur$id, retry = cur$retry)
        }
        reset(); next
      }
      if (startsWith(ln, ":")) next                         # comment / keep-alive
      p <- regexpr(":", ln, fixed = TRUE)
      if (p < 0) { field <- ln; value <- "" } else {
        field <- substr(ln, 1L, p - 1L); value <- substr(ln, p + 1L, nchar(ln))
        if (startsWith(value, " ")) value <- substr(value, 2L, nchar(value))
      }
      switch(field,
        event = { cur$event <<- value; cur$has_field <<- TRUE },
        data  = { cur$data <<- c(cur$data, value); cur$has_field <<- TRUE },
        id    = { cur$id <<- value; cur$has_field <<- TRUE },
        retry = { if (grepl("^[0-9]+$", value)) cur$retry <<- as.integer(value) },
        NULL)
    }
    events
  }
  list(feed = feed)
}

now <- function() as.numeric(Sys.time())
```
Note for implementers: `c(buf, bytes)` plus `which()` over the whole buffer is O(n) per chunk; fine for SSE-sized buffers, but a production parser should scan only the new bytes (httr2 fixed the equivalent quadratic behaviour of `resp_stream_lines()`/`resp_stream_sse()`/`resp_stream_aws()` in 1.2.3, released 2026-06-23 — "decode whole chunks at a time, holding results in a queue" — not in the installed 1.2.2, whose NEWS has no such entry).

### 5.2 Prototype (a): N concurrent SSE streams in one R process (`p1_curl_multi.R`)

```r
# p1_curl_multi.R -- PROTOTYPE (a): N concurrent SSE streams consumed in ONE R process through one
# curl multi pool with per-handle `data` callbacks. Compares curl's defaults (PIPEWAIT on since curl 6.1.0)
# with pipewait = 0, and reports wall time, per-stream finish, interleaving and CPU time used while waiting.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/15"
source(file.path(W, "mock_sse_base.R")); source(file.path(W, "sse.R"))
srv <- start_mock_sse(); base <- srv$url
cat("mock server (base R sockets) at", base, "| curl", as.character(packageVersion("curl")),
    "| libcurl", curl::curl_version()$version, "\n")

plan <- data.frame(id = c("A", "B", "C", "D", "E", "F"), n = c(10, 5, 20, 8, 4, 12),
                   delay = c(0.10, 0.30, 0.05, 0.25, 0.20, 0.12), stringsAsFactors = FALSE)
plan$sched <- (plan$n + 1) * plan$delay   # token i at i*delay, "done" one delay after the last token

run_streams <- function(plan, pipewait) {
  pool <- curl::new_pool(total_con = 100, host_con = 100)
  log <- data.frame(t = numeric(), id = character(), stringsAsFactors = FALSE); state <- list()
  t0 <- now(); cpu0 <- proc.time()
  for (k in seq_len(nrow(plan))) local({
    id <- plan$id[k]
    st <- new.env(); st$parser <- sse_parser(); st$tokens <- character(); st$t_done <- NA
    state[[id]] <<- st
    h <- curl::new_handle(url = sprintf("%s/sse?id=%s&n=%d&delay=%s", base, id, plan$n[k], plan$delay[k]))
    curl::handle_setheaders(h, Accept = "text/event-stream")
    if (!is.null(pipewait)) curl::handle_setopt(h, pipewait = pipewait)
    curl::multi_add(h, pool = pool,
      data = function(bytes, final = FALSE) {
        for (ev in st$parser$feed(bytes, final)) if (ev$event == "token") {
          st$tokens <- c(st$tokens, jsonlite::fromJSON(ev$data)$t)
          log[nrow(log) + 1L, ] <<- list(now() - t0, id)
        }
      },
      done = function(res) { st$status <- res$status_code; st$t_done <- now() - t0 },
      fail = function(msg) { st$error <- msg; st$t_done <- now() - t0 })
  })
  iter <- 0L
  repeat {   # the event loop: blocks in poll() for <= 100 ms, returns early when a transfer completes
    r <- curl::multi_run(timeout = 0.1, poll = TRUE, pool = pool); iter <- iter + 1L
    if (r$pending == 0L) break
  }
  cpu <- proc.time() - cpu0
  list(wall = now() - t0, cpu = unname(cpu["user.self"] + cpu["sys.self"]), log = log, state = state, iter = iter)
}

report <- function(label, res) {
  switches <- sum(res$log$id[-1] != res$log$id[-nrow(res$log)])
  fin <- vapply(plan$id, function(i) res$state[[i]]$t_done, 0)
  ntok <- vapply(plan$id, function(i) length(res$state[[i]]$tokens), 1L)
  cat(sprintf("\n== %s\n  finished at: %s\n  tokens: %s\n  WALL %.2fs | slowest stream by schedule %.2fs | sum of schedules %.2fs | CPU %.2fs | loop iterations %d | stream switches %d\n",
    label, paste(sprintf("%s=%.2f", plan$id, fin), collapse = " "), paste(ntok, collapse = " "),
    res$wall, max(plan$sched), sum(plan$sched), res$cpu, res$iter, switches))
  cat("  first 24 arrivals:", paste(sprintf("%.2f:%s", head(res$log$t, 24), head(res$log$id, 24)), collapse = " "), "\n")
  invisible(list(ok = res$wall < max(plan$sched) + 0.4 && all(ntok == plan$n) && switches > 10))
}

r_default <- run_streams(plan, pipewait = NULL)
report("curl defaults (new_pool host_con=100; handle PIPEWAIT left at curl's default)", r_default)
r_fixed <- run_streams(plan, pipewait = 0L)
ok <- report("pipewait = 0 on every handle", r_fixed)$ok
cat("\n", if (ok) "[PASS]" else "[FAIL]", " 6 streams interleaved; wall close to the slowest stream\n", sep = "")

# scale: 20 streams of 10 tokens x 0.2 s (2.2 s each by schedule)
plan20 <- data.frame(id = sprintf("S%02d", 1:20), n = 10, delay = 0.2, stringsAsFactors = FALSE); plan20$sched <- 2.2
plan_bak <- plan; plan <- plan20
r20 <- run_streams(plan20, pipewait = 0L)
cat(sprintf("\n20 streams x 2.2 s each: WALL %.2fs, CPU %.2fs, all complete: %s\n", r20$wall, r20$cpu,
    all(vapply(plan20$id, function(i) length(r20$state[[i]]$tokens), 1L) == 10)))
srv$stop()
```
Output (second run, `p1_output.txt`):
```
mock server (base R sockets) at http://127.0.0.1:35988 | curl 7.0.0 | libcurl 8.14.1 

== curl defaults (new_pool host_con=100; handle PIPEWAIT left at curl's default)
  finished at: A=1.22 B=3.04 C=2.30 D=3.51 E=2.26 F=2.83
  tokens: 10 5 20 8 4 12
  WALL 3.51s | slowest stream by schedule 2.25s | sum of schedules 8.76s | CPU 0.67s | loop iterations 9 | stream switches 40
  first 24 arrivals: 0.26:A 0.32:A 0.42:A 0.53:A 0.62:A 0.73:A 0.83:A 0.92:A 1.03:A 1.12:A 1.30:C 1.35:C 1.40:F 1.41:C 1.45:C 1.46:E 1.51:C 1.51:D 1.51:F 1.54:B 1.56:C 1.60:C 1.63:F 1.65:C 

== pipewait = 0 on every handle
  finished at: A=1.12 B=1.82 C=1.09 D=2.30 E=1.05 F=1.62
  tokens: 10 5 20 8 4 12
  WALL 2.30s | slowest stream by schedule 2.25s | sum of schedules 8.76s | CPU 0.44s | loop iterations 9 | stream switches 51
  first 24 arrivals: 0.09:C 0.12:A 0.14:C 0.18:F 0.19:C 0.32:A 0.32:A 0.32:C 0.32:C 0.32:D 0.33:E 0.33:F 0.33:B 0.34:C 0.39:C 0.42:F 0.42:A 0.44:C 0.45:E 0.49:C 0.52:A 0.54:F 0.54:C 0.54:D 

[PASS] 6 streams interleaved; wall close to the slowest stream

20 streams x 2.2 s each: WALL 2.34s, CPU 0.59s, all complete: TRUE
```
First run: defaults 3.46 s, pipewait 0 2.29 s, 20 streams 2.33 s. The diagnosis script `a2_pool_diag.R` output is quoted in §2.2.

### 5.3 httr2 and promise variants (`p2_httr2_variants.R`)

```r
# p2_httr2_variants.R -- the same 6-stream workload through httr2's APIs:
#   V1 req_perform_connection(blocking = FALSE) + round-robin resp_stream_sse() polling
#   V2 ellmer's pattern: coro async generator per stream + later::later_fd() on resp$body$get_fdset()
#   V3 req_perform_promise() (whole body, no streaming) x 6, event loop driven by later::run_now()
#   V4 req_perform_parallel() (whole body) x 6
# Reports wall time, CPU time, and whether stream 1 blocks the others (PIPEWAIT effect).
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/15"
source(file.path(W, "mock_sse_base.R"))
suppressPackageStartupMessages({ library(httr2); library(coro) })
now <- function() as.numeric(Sys.time())
srv <- start_mock_sse(); base <- srv$url
cat("httr2", as.character(packageVersion("httr2")), "| later", as.character(packageVersion("later")),
    "| promises", as.character(packageVersion("promises")), "| coro", as.character(packageVersion("coro")), "\n")
plan <- data.frame(id = c("A", "B", "C", "D", "E", "F"), n = c(10, 5, 20, 8, 4, 12),
                   delay = c(0.10, 0.30, 0.05, 0.25, 0.20, 0.12), stringsAsFactors = FALSE)
plan$sched <- (plan$n + 1) * plan$delay
mkreq <- function(k, pipewait = NULL) {
  r <- request(sprintf("%s/sse?id=%s&n=%d&delay=%s", base, plan$id[k], plan$n[k], plan$delay[k]))
  if (!is.null(pipewait)) r <- req_options(r, pipewait = pipewait)
  r
}
line <- function(label, wall, cpu, fin, extra = "") cat(sprintf("%-58s WALL %.2fs CPU %.2fs | finish %s %s\n",
  label, wall, cpu, paste(sprintf("%s=%.2f", plan$id, fin), collapse = " "), extra))
cpu_now <- function() { p <- proc.time(); unname(p["user.self"] + p["sys.self"]) }

## V1 ------------------------------------------------------------------------------------------
v1 <- function(pipewait) {
  t0 <- now(); c0 <- cpu_now(); t_open <- numeric()
  resps <- lapply(seq_len(nrow(plan)), function(k) { r <- req_perform_connection(mkreq(k, pipewait), blocking = FALSE); t_open[k] <<- now() - t0; r })
  fin <- rep(NA_real_, nrow(plan)); ntok <- integer(nrow(plan)); polls <- 0L
  while (anyNA(fin)) {
    for (k in which(is.na(fin))) {
      repeat {
        polls <- polls + 1L
        ev <- resp_stream_sse(resps[[k]])
        if (is.null(ev)) { if (resp_stream_is_complete(resps[[k]])) { fin[k] <- now() - t0; close(resps[[k]]) }; break }
        if (ev$type == "token") ntok[k] <- ntok[k] + 1L
        if (ev$type == "done") { fin[k] <- now() - t0; close(resps[[k]]); break }
      }
    }
  }
  line(sprintf("V1 connection(blocking=FALSE) round robin, pipewait=%s", format(pipewait %||% "default")),
       now() - t0, cpu_now() - c0, fin, sprintf("| opened at %s | polls %d | tokens ok %s",
       paste(sprintf("%.2f", t_open), collapse = ","), polls, all(ntok == plan$n)))
}
`%||%` <- function(a, b) if (is.null(a)) b else a
v1(NULL); v1(0L)

## V2 ------------------------------------------------------------------------------------------
v2 <- function(pipewait) {
  t0 <- now(); c0 <- cpu_now(); fin <- rep(NA_real_, nrow(plan)); ntok <- integer(nrow(plan))
  stream_events <- async_generator(function(req) {          # ellmer::chat_perform_async_stream, simplified
    resp <- req_perform_connection(req, blocking = FALSE)
    on.exit(close(resp))
    repeat {
      ev <- resp_stream_sse(resp)
      if (is.null(ev) && !resp_stream_is_complete(resp)) {
        fds <- resp$body$get_fdset()
        await(promises::promise(function(resolve, reject)
          later::later_fd(resolve, fds$reads, fds$writes, fds$exceptions, fds$timeout)))
        next
      }
      if (is.null(ev)) break
      yield(ev)
    }
  })
  consume <- async(function(k) {
    for (ev in await_each(stream_events(mkreq(k, pipewait)))) {
      if (ev$type == "token") ntok[k] <<- ntok[k] + 1L
      if (ev$type == "done") break
    }
    fin[k] <<- now() - t0
    k
  })
  ps <- lapply(seq_len(nrow(plan)), consume)
  all_done <- FALSE
  promises::then(promises::promise_all(.list = ps), function(v) all_done <<- TRUE)
  ticks <- 0L
  while (!all_done) { later::run_now(timeoutSecs = 0.1); ticks <- ticks + 1L }
  line(sprintf("V2 coro async gen + later_fd (ellmer), pipewait=%s", format(pipewait %||% "default")),
       now() - t0, cpu_now() - c0, fin, sprintf("| run_now ticks %d | tokens ok %s", ticks, all(ntok == plan$n)))
}
v2(NULL); v2(0L)

## V3 ------------------------------------------------------------------------------------------
v3 <- function(pipewait) {
  t0 <- now(); c0 <- cpu_now(); fin <- rep(NA_real_, nrow(plan)); pool <- curl::new_pool(host_con = 100)
  ps <- lapply(seq_len(nrow(plan)), function(k) promises::then(req_perform_promise(mkreq(k, pipewait), pool = pool),
    function(resp) { fin[k] <<- now() - t0; resp }))
  done <- FALSE; promises::then(promises::promise_all(.list = ps), function(v) done <<- TRUE)
  while (!done) later::run_now(timeoutSecs = 0.1)
  line(sprintf("V3 req_perform_promise x6 (no streaming), pipewait=%s", format(pipewait %||% "default")),
       now() - t0, cpu_now() - c0, fin)
}
v3(NULL); v3(0L)

## V4 ------------------------------------------------------------------------------------------
v4 <- function(pipewait) {
  t0 <- now(); c0 <- cpu_now()
  resps <- req_perform_parallel(lapply(seq_len(nrow(plan)), mkreq, pipewait = pipewait), progress = FALSE, max_active = 10)
  line(sprintf("V4 req_perform_parallel x6 (no streaming), pipewait=%s", format(pipewait %||% "default")),
       now() - t0, cpu_now() - c0, rep(NA_real_, nrow(plan)), sprintf("| statuses %s", paste(vapply(resps, resp_status, 1L), collapse = ",")))
}
v4(NULL); v4(0L)
cat(sprintf("schedule: slowest stream %.2fs, sum %.2fs\n", max(plan$sched), sum(plan$sched)))
srv$stop()
```
Output (second run, `p2_output.txt`):
```
httr2 1.2.2 | later 1.4.8 | promises 1.5.0 | coro 1.1.0 
V1 connection(blocking=FALSE) round robin, pipewait=default WALL 2.44s CPU 0.21s | finish A=1.21 B=1.97 C=1.23 D=2.44 E=1.25 F=1.78 | opened at 0.07,0.15,0.18,0.20,0.21,0.22 | polls 217 | tokens ok TRUE
V1 connection(blocking=FALSE) round robin, pipewait=0      WALL 2.32s CPU 0.11s | finish A=1.14 B=1.83 C=1.11 D=2.31 E=1.08 F=1.67 | opened at 0.01,0.02,0.04,0.07,0.08,0.10 | polls 217 | tokens ok TRUE
V2 coro async gen + later_fd (ellmer), pipewait=default    WALL 2.53s CPU 0.93s | finish A=1.25 B=2.03 C=1.31 D=2.53 E=1.31 F=1.89 | run_now ticks 145 | tokens ok TRUE
V2 coro async gen + later_fd (ellmer), pipewait=0          WALL 2.40s CPU 0.81s | finish A=1.14 B=1.86 C=1.15 D=2.39 E=1.17 F=1.75 | run_now ticks 141 | tokens ok TRUE
V3 req_perform_promise x6 (no streaming), pipewait=default WALL 3.45s CPU 0.05s | finish A=1.17 B=2.98 C=2.24 D=3.45 E=2.22 F=2.77 
V3 req_perform_promise x6 (no streaming), pipewait=0       WALL 2.31s CPU 0.05s | finish A=1.13 B=1.83 C=1.11 D=2.31 E=1.07 F=1.63 
V4 req_perform_parallel x6 (no streaming), pipewait=default WALL 3.42s CPU 0.04s | finish A=NA B=NA C=NA D=NA E=NA F=NA | statuses 200,200,200,200,200,200
V4 req_perform_parallel x6 (no streaming), pipewait=0      WALL 2.32s CPU 0.03s | finish A=NA B=NA C=NA D=NA E=NA F=NA | statuses 200,200,200,200,200,200
schedule: slowest stream 2.25s, sum 8.76s
```

### 5.4 Headline prototype: interleaved inline agents with tools on a shared object (`p3_inline_agents.R`)

```r
# p3_inline_agents.R -- PROTOTYPE (a+c, the headline): N inline sub-agents interleaved in ONE R process.
# Each agent is an explicit state machine (an environment). One reactor loop:
#   * multiplexes every agent's streaming HTTP call on one curl multi pool (data callbacks -> SSE parser
#     -> Anthropic event assembler), waiting with processx::poll() on curl's sockets (+ any child processes);
#   * runs queued tool calls ONE AT A TIME on the main R thread, in the agent's own child environment
#     (new.env(parent = caller)): reads fall through to the caller's objects with zero copy, writes stay local;
#   * limits how many agents are active at once (max_active).
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/15"
RLIB <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
.libPaths(c(RLIB, .libPaths()))   # lobstr lives in the private library
source(file.path(W, "mock_sse_base.R")); source(file.path(W, "sse.R"))
now <- function() as.numeric(Sys.time())
`%||%` <- function(a, b) if (is.null(a)) b else a
rss_mb <- function() round(ps::ps_memory_info(ps::ps_handle())[["rss"]] / 2^20)

## ---- Anthropic stream assembler: SSE events -> assistant message ------------------------------
anthropic_assembler <- function() {
  blocks <- list(); json_buf <- list(); stop_reason <- NULL; usage <- list(input = 0, output = 0)
  list(
    event = function(ev) {
      d <- jsonlite::fromJSON(ev$data, simplifyVector = FALSE)
      switch(ev$event,
        message_start = { usage$input <<- d$message$usage$input_tokens %||% 0 },
        content_block_start = { i <- d$index + 1L; blocks[[i]] <<- d$content_block; json_buf[[i]] <<- "" },
        content_block_delta = {
          i <- d$index + 1L
          if (d$delta$type == "text_delta") blocks[[i]]$text <<- paste0(blocks[[i]]$text, d$delta$text)
          if (d$delta$type == "input_json_delta") json_buf[[i]] <<- paste0(json_buf[[i]], d$delta$partial_json)
        },
        content_block_stop = { i <- d$index + 1L
          if (identical(blocks[[i]]$type, "tool_use") && nzchar(json_buf[[i]]))
            blocks[[i]]$input <<- jsonlite::fromJSON(json_buf[[i]], simplifyVector = FALSE) },
        message_delta = { stop_reason <<- d$delta$stop_reason; usage$output <<- d$usage$output_tokens %||% 0 },
        NULL)
      if (ev$event == "content_block_delta" && d$delta$type == "text_delta") d$delta$text else NULL
    },
    message = function() list(role = "assistant", content = blocks, stop_reason = stop_reason, usage = usage)
  )
}

## ---- tools: the `r` tool evaluates code in the agent's environment ----------------------------
run_r_tool <- function(code, envir) {
  out <- utils::capture.output(val <- tryCatch(withVisible(eval(parse(text = code), envir = envir)),
                                               error = function(e) list(value = e, visible = TRUE)))
  if (inherits(val$value, "error")) return(list(text = conditionMessage(val$value), is_error = TRUE))
  if (val$visible) out <- c(out, utils::capture.output(print(val$value)))
  list(text = paste(out, collapse = "\n"), is_error = FALSE)
}

## ---- agent state machine -------------------------------------------------------------------
new_agent <- function(name, task, plan, caller_env, url) {
  a <- new.env(parent = emptyenv())
  a$name <- name; a$state <- "queued"; a$url <- url; a$plan <- plan
  a$env <- new.env(parent = caller_env)          # the overlay: reads fall through, writes stay here
  a$messages <- list(list(role = "user", content = task))
  a$usage <- c(input = 0, output = 0); a$turns <- 0L; a$text <- character(); a$tool_queue <- list()
  a
}

reactor_run <- function(agents, max_active = Inf, log = function(...) NULL) {
  pool <- curl::new_pool(total_con = 100, host_con = 100)
  tool_queue <- list()            # global FIFO of list(agent, block): tools run one at a time
  t0 <- now()
  start_call <- function(a) {
    a$state <- "streaming"; a$turns <- a$turns + 1L
    a$parser <- sse_parser(); a$asm <- anthropic_assembler()
    body <- list(model = "mock-1", stream = TRUE, max_tokens = 1024L, messages = a$messages, mock = a$plan)
    h <- curl::new_handle(url = paste0(a$url, "/v1/messages"), post = TRUE, pipewait = 0L,
                          postfields = as.character(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null")))
    curl::handle_setheaders(h, "content-type" = "application/json", accept = "text/event-stream")
    curl::multi_add(h, pool = pool,
      data = function(bytes, final = FALSE) for (ev in a$parser$feed(bytes, final)) {
        txt <- a$asm$event(ev); if (!is.null(txt)) log(now() - t0, a$name, "token", trimws(txt))
      },
      done = function(res) {
        msg <- a$asm$message()
        a$usage <- a$usage + c(msg$usage$input, msg$usage$output)
        a$messages[[length(a$messages) + 1L]] <- msg[c("role", "content")]
        a$text <- c(a$text, unlist(lapply(msg$content, function(b) if (b$type == "text") b$text)))
        calls <- Filter(function(b) identical(b$type, "tool_use"), msg$content)
        if (identical(msg$stop_reason, "tool_use") && length(calls)) {
          a$state <- "tools"; a$pending_results <- list(); a$n_calls <- length(calls)
          for (b in calls) tool_queue[[length(tool_queue) + 1L]] <<- list(agent = a, block = b)
        } else { a$state <- "done"; a$t_done <- now() - t0; log(now() - t0, a$name, "done", "") }
      },
      fail = function(msg) { a$state <- "error"; a$error <- msg; log(now() - t0, a$name, "error", msg) })
  }
  repeat {
    active <- sum(vapply(agents, function(a) a$state %in% c("streaming", "tools"), NA))
    for (a in agents) if (a$state == "queued" && active < max_active) { start_call(a); active <- active + 1L }
    for (a in agents) if (a$state == "ready") start_call(a)
    if (all(vapply(agents, function(a) a$state %in% c("done", "error"), NA))) break
    if (length(tool_queue)) {                       # run exactly one tool, then service the network again
      job <- tool_queue[[1]]; tool_queue[[1]] <- NULL; a <- job$agent
      log(now() - t0, a$name, "tool_start", job$block$input$code)
      res <- run_r_tool(job$block$input$code, a$env)
      log(now() - t0, a$name, "tool_end", substr(gsub("\n", " ", res$text), 1, 60))
      a$pending_results[[length(a$pending_results) + 1L]] <- list(type = "tool_result",
        tool_use_id = job$block$id, content = res$text, is_error = res$is_error)
      if (length(a$pending_results) == a$n_calls) {
        a$messages[[length(a$messages) + 1L]] <- list(role = "user", content = a$pending_results)
        a$state <- "ready"
      }
      curl::multi_run(timeout = 0, pool = pool)     # drain whatever arrived while the tool ran
      next
    }
    fds <- curl::multi_fdset(pool = pool)
    processx::poll(list(processx::curl_fds(fds)), as.integer(min(100, max(1, 1000 * fds$timeout))))
    curl::multi_run(timeout = 0, pool = pool)       # perform the ready transfers, fire callbacks
  }
  now() - t0
}

## ---- the demo --------------------------------------------------------------------------------
srv <- start_mock_sse(); base <- srv$url
caller <- new.env()                                  # stands in for the user's global environment
local(big <- stats::runif(5e7), envir = caller)   # 5e7 materialised doubles = 381 MB (not an ALTREP sequence)
cat(sprintf("caller has `big`: %s, %.0f MB, address %s | process RSS %d MB\n", class(caller$big),
  as.numeric(object.size(caller$big)) / 2^20, lobstr::obj_addr(caller$big), rss_mb()))
big_addr <- lobstr::obj_addr(caller$big)

plans <- list(
  stats  = list(name = "stats",  tokens = 8, delay = 0.10, tool_code = "m <- mean(big); m"),
  sizes  = list(name = "sizes",  tokens = 6, delay = 0.15, tool_code = "Sys.sleep(0.5); n <- length(big); n"),
  addr   = list(name = "addr",   tokens = 10, delay = 0.08, tool_code = sprintf("identical(lobstr::obj_addr(big), '%s')", big_addr)),
  write  = list(name = "write",  tokens = 5, delay = 0.20, tool_code = "big <- big[1:3] * 0; head(big)"),
  quant  = list(name = "quant",  tokens = 7, delay = 0.12, tool_code = "q <- quantile(big[seq(1, length(big), by = 1000)], c(.1, .9)); q")
)
mk <- function() lapply(names(plans), function(nm) new_agent(nm, paste("Task for", nm), plans[[nm]], caller, base))

events <- data.frame(t = numeric(), agent = character(), kind = character(), what = character(), stringsAsFactors = FALSE)
logger <- function(t, agent, kind, what) events[nrow(events) + 1L, ] <<- list(round(t, 2), agent, kind, what)

agents <- mk(); rss0 <- rss_mb()
wall_conc <- reactor_run(agents, max_active = 5, log = logger)
rss1 <- rss_mb()
cat(sprintf("\nconcurrent (max_active = 5): WALL %.2fs | RSS before %d MB, after %d MB\n", wall_conc, rss0, rss1))
for (a in agents) cat(sprintf("  %-6s state=%s turns=%d usage in/out=%d/%d done at %.2fs | final text: %s\n", a$name, a$state, a$turns,
  a$usage[1], a$usage[2], a$t_done, trimws(tail(a$text, 1))))
cat("\ntool calls in execution order (never overlapping):\n")
print(events[events$kind %in% c("tool_start", "tool_end"), ], row.names = FALSE)
tok <- events[events$kind == "token", ]
cat("\ntoken arrivals 0.0-1.0 s (agent interleaving):", paste(sprintf("%.2f:%s", tok$t[tok$t < 1], tok$agent[tok$t < 1]), collapse = " "), "\n")
# tokens that arrived while the 0.5 s tool of `sizes` was running are delivered right after it
ts <- events$t[events$kind == "tool_start" & events$agent == "sizes"]; te <- events$t[events$kind == "tool_end" & events$agent == "sizes"]
cat(sprintf("tokens recorded during sizes' 0.5 s tool (%.2f-%.2f): %d; recorded within 0.05 s after it: %d\n",
  ts, te, sum(tok$t > ts & tok$t < te), sum(tok$t >= te & tok$t < te + 0.05)))

cat("\nisolation checks:\n")
cat("  caller$big untouched:", identical(length(caller$big), 5e7L) && lobstr::obj_addr(caller$big) == big_addr, "\n")
cat("  agent 'write' has its own local `big` of length", length(agents[[4]]$env$big), "\n")
cat("  agent 'stats' local objects:", paste(ls(agents[[1]]$env), collapse = ","), "| caller objects:", paste(ls(caller), collapse = ","), "\n")
cat("  agent 'addr' saw the caller's big at the same address (zero copy):", agents[[3]]$messages[[3]]$content[[1]]$content, "\n")

agents2 <- mk()
wall_seq <- reactor_run(agents2, max_active = 1)
agents3 <- mk()
wall_two <- reactor_run(agents3, max_active = 2)
cat(sprintf("\nsame 5 agents: max_active=1 (sequential) %.2fs | max_active=2 %.2fs | max_active=5 %.2fs\n", wall_seq, wall_two, wall_conc))
srv$stop()
```
Output (`p3_output.txt`, load ~50-110; RSS is shown but is not reliable on this machine, see header):
```
caller has `big`: numeric, 381 MB, address 0x150000000 | process RSS 483 MB

concurrent (max_active = 5): WALL 5.34s | RSS before 483 MB, after 492 MB
  stats  state=done turns=2 usage in/out=200/36 done at 3.48s | final text: stats-final-1 ... stats-final-8
  sizes  state=done turns=2 usage in/out=200/32 done at 4.77s | final text: sizes-final-1 ... sizes-final-6
  addr   state=done turns=2 usage in/out=200/40 done at 3.08s | final text: addr-final-1 ... addr-final-10
  write  state=done turns=2 usage in/out=200/30 done at 5.34s | final text: write-final-1 ... write-final-5
  quant  state=done turns=2 usage in/out=200/34 done at 3.81s | final text: quant-final-1 ... quant-final-7

tool calls in execution order (never overlapping):
    t agent       kind
 1.85  addr tool_start      identical(lobstr::obj_addr(big), '0x150000000')   -> [1] TRUE
 1.85  addr   tool_end
 1.96 stats tool_start      m <- mean(big); m                                  -> [1] 0.5000868
 2.16 stats   tool_end
 2.34 quant tool_start      q <- quantile(big[seq(1, length(big), by = 1000)], c(.1, .9)); q
 2.35 quant   tool_end                                                         -> 10% 0.0998105 90% 0.8987197
 2.58 sizes tool_start      Sys.sleep(0.5); n <- length(big); n                -> [1] 50000000
 3.08 sizes   tool_end
 3.29 write tool_start      big <- big[1:3] * 0; head(big)                     -> [1] 0 0 0
 3.29 write   tool_end

token arrivals 0.0-1.0 s (agent interleaving): 0.46:stats 0.49:addr 0.56:stats 0.57:addr 0.63:sizes 0.65:addr 0.66:stats 0.66:quant 0.73:addr 0.76:stats 0.77:sizes 0.78:quant 0.81:addr 0.86:stats 0.89:addr 0.89:write 0.90:quant 0.93:sizes 0.96:stats 0.97:addr 
tokens recorded during sizes' 0.5 s tool (2.58-3.08): 0; recorded within 0.05 s after it: 14

isolation checks:
  caller$big untouched: TRUE 
  agent 'write' has its own local `big` of length 3 
  agent 'stats' local objects: m | caller objects: big 
  agent 'addr' saw the caller's big at the same address (zero copy): [1] TRUE 

same 5 agents: max_active=1 (sequential) 14.04s | max_active=2 10.31s | max_active=5 5.34s
```
(The final-text lines are abbreviated with "..." here; the tool table is re-arranged for width, values unchanged.) Earlier runs: 5.27/8.79/14.45 s, 5.18/8.72/14.32 s, 6.06/9.77/14.83 s (concurrent/2/sequential). The first run used `as.numeric(seq_len(5e7))`, which is a compact ALTREP sequence; I replaced it with `runif()` so the object is real memory.

### 5.5 Prototype (c): child environment — zero-copy reads, isolated writes, escape hatches, guard (`p5_child_env.R`)

```r
# p5_child_env.R -- PROTOTYPE (c): an inline sub-agent evaluates code in new.env(parent = caller).
# Proves zero-copy reads and isolated writes, then shows every way a write can still escape, and
# measures a binding-lock guard that turns the commonest escape (`<<-`) into an error.
RLIB <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
.libPaths(c(RLIB, .libPaths()))
vcells_mb <- function() { g <- gc(); g[2, 2] }       # R heap in use for vectors, MB (R's own accounting)
say <- function(...) cat(sprintf(...), "\n")
run_in <- function(code, env) eval(parse(text = code), envir = env)

caller <- globalenv()                                 # the user's workspace, as for a top-level gptr() call
assign("big", stats::runif(5e7), caller)              # 381 MB
assign("counter", 0, caller)
assign("cfg", new.env(), caller); caller$cfg$level <- 1   # a reference object (like R6 / Seurat's environments)
assign("bump", function() counter <<- counter + 100, caller)  # a user function with a side effect
dt_ok <- requireNamespace("data.table", quietly = TRUE)
if (dt_ok) assign("dt", data.table::data.table(a = 1:3), caller)
addr0 <- lobstr::obj_addr(caller$big)

say("== 1. zero-copy reads")
agent <- new.env(parent = caller)
v0 <- vcells_mb()
m <- run_in("mean(big)", agent)
v1 <- vcells_mb()
say("mean(big) evaluated in the agent env = %.4f | R heap before %.1f MB, after %.1f MB (delta %.1f MB)", m, v0, v1, v1 - v0)
say("address of big seen from the agent == caller's: %s", run_in("lobstr::obj_addr(big)", agent) == addr0)
tracemem_out <- utils::capture.output({ tracemem(caller$big); invisible(run_in("s <- sum(big); f <- function() length(big); f()", agent)); untracemem(caller$big) })
say("tracemem() reported copies during reads: %d", length(tracemem_out))

say("\n== 2. writes stay local (copy-on-modify)")
v0 <- vcells_mb()
run_in("big <- big * 2; note <- 'agent result'", agent)
v1 <- vcells_mb()
say("agent now has: %s | caller still has big with mean %.4f, address unchanged: %s", paste(ls(agent), collapse = ","),
    mean(caller$big), lobstr::obj_addr(caller$big) == addr0)
say("the local modified copy cost %.1f MB of R heap (a full copy, owned by the agent env)", v1 - v0)
rm(list = ls(agent), envir = agent); invisible(gc())

say("\n== 3. escape hatches (what new.env(parent = caller) does NOT stop)")
run_in("counter <<- counter + 1", agent)
say("a. `counter <<- counter + 1` in the agent env -> caller$counter = %g (MODIFIED)", caller$counter)
run_in("bump()", agent)
say("b. calling a caller-defined function with `<<-` -> caller$counter = %g (MODIFIED)", caller$counter)
run_in("cfg$level <- 2", agent)
say("c. `cfg$level <- 2` on an environment object -> caller$cfg$level = %g (MODIFIED: reference semantics)", caller$cfg$level)
if (dt_ok) { run_in("dt[, b := a * 10]", agent); say("d. data.table `dt[, b := a * 10]` -> caller's dt columns: %s (MODIFIED in place)", paste(names(caller$dt), collapse = ",")) }
run_in("assign('leak', 1, envir = globalenv())", agent)
say("e. assign(..., envir = globalenv()) -> exists('leak') in caller: %s (MODIFIED)", exists("leak", envir = caller, inherits = FALSE))
run_in("brand_new <<- 42", agent)
say("f. `brand_new <<- 42` (name exists nowhere) -> created in globalenv: %s", exists("brand_new", envir = globalenv(), inherits = FALSE))
seed0 <- get(".Random.seed", globalenv()); run_in("x <- runif(1)", agent)
say("g. runif() in the agent changes globalenv's .Random.seed: %s (RNG state is process-global)", !identical(seed0, get(".Random.seed", globalenv())))
run_in("rm(big)", agent) |> tryCatch(warning = function(w) say("h. rm(big) in the agent -> warning '%s'; caller keeps big: %s", conditionMessage(w), exists("big", caller)))

say("\n== 4. guard: lock the caller's bindings while agent code runs")
with_locked_bindings <- function(env, expr) {
  nms <- ls(env, all.names = TRUE)
  newly <- nms[!vapply(nms, bindingIsLocked, NA, env = env)]
  for (n in newly) tryCatch(lockBinding(n, env), error = function(e) {
    # a top-level for() index is an unboxed "immediate" binding: lockBinding() says "bad binding access".
    # Re-assigning the same value boxes it; then it can be locked.
    assign(n, get(n, envir = env, inherits = FALSE), envir = env); lockBinding(n, env)
  })
  on.exit(for (n in newly) if (exists(n, envir = env, inherits = FALSE)) unlockBinding(n, env), add = TRUE)
  before <- nms
  val <- tryCatch(expr, error = function(e) e)
  created <- setdiff(ls(env, all.names = TRUE), before)
  list(value = val, created = created)
}
caller$counter <- 0
r <- with_locked_bindings(caller, run_in("counter <<- counter + 1", agent))
say("`counter <<- counter + 1` under the guard -> %s | caller$counter = %g",
    if (inherits(r$value, "error")) paste("error:", conditionMessage(r$value)) else "no error", caller$counter)
r <- with_locked_bindings(caller, run_in("another_new <<- 1; 'ok'", agent))
say("`another_new <<- 1` under the guard -> not blocked (new binding) but detected: created = %s", paste(r$created, collapse = ","))
r <- with_locked_bindings(caller, run_in("cfg$level <- 3; 'ok'", agent))
say("`cfg$level <- 3` under the guard -> not blocked (value inside a reference object): caller$cfg$level = %g", caller$cfg$level)
say("bindings are unlocked again afterwards: counter locked = %s", bindingIsLocked("counter", caller))
# cost of the guard with 2000 objects in the workspace
for (i in 1:2000) assign(sprintf("obj%04d", i), i, caller)
t <- system.time(for (k in 1:10) with_locked_bindings(caller, run_in("1 + 1", agent)))[["elapsed"]] / 10
say("guard overhead with %d bindings in the workspace: %.1f ms per tool call", length(ls(caller)), 1000 * t)
rm(list = sprintf("obj%04d", 1:2000), envir = caller)

say("\n== 5. two inline agents, separate overlays, explicit export with conflict policy")
a1 <- new.env(parent = caller); a2 <- new.env(parent = caller)
run_in("res <- mean(big); fit <- 'lm from a1'", a1); run_in("res <- median(big[1:1e6])", a2)
gptr_export <- function(from, names, to, conflict = c("error", "rename", "overwrite"), tag = "agent") {
  conflict <- match.arg(conflict); out <- character()
  for (n in names) {
    dest <- n
    if (exists(n, envir = to, inherits = FALSE)) {
      if (conflict == "error") stop(sprintf("export would overwrite `%s` in the target environment", n), call. = FALSE)
      if (conflict == "rename") dest <- make.unique(c(ls(to, all.names = TRUE), paste0(n, "_", tag)))[length(ls(to, all.names = TRUE)) + 1L]
    }
    assign(dest, get(n, envir = from, inherits = FALSE), envir = to); out[n] <- dest
  }
  out
}
say("a1 exports res -> %s", paste(gptr_export(a1, "res", caller, tag = "a1"), collapse = ","))
e <- tryCatch(gptr_export(a2, "res", caller, tag = "a2"), error = function(e) conditionMessage(e))
say("a2 exports res with conflict='error' -> %s", e)
say("a2 exports res with conflict='rename' -> %s", paste(gptr_export(a2, "res", caller, conflict = "rename", tag = "a2"), collapse = ","))
say("caller now has: %s", paste(setdiff(ls(caller), c("a1", "a2", "agent", "addr0", "caller", "dt_ok", "e", "m", "r", "RLIB", "run_in", "say", "seed0", "t", "tracemem_out", "v0", "v1", "vcells_mb", "with_locked_bindings", "gptr_export", "i", "k")), collapse = ","))
```
Output (`p5_output.txt`):
```
== 1. zero-copy reads 
mean(big) evaluated in the agent env = 0.5000 | R heap before 386.7 MB, after 387.7 MB (delta 1.0 MB) 
address of big seen from the agent == caller's: TRUE 
tracemem() reported copies during reads: 0 

== 2. writes stay local (copy-on-modify) 
agent now has: big,f,note,s | caller still has big with mean 0.5000, address unchanged: TRUE 
the local modified copy cost 381.5 MB of R heap (a full copy, owned by the agent env) 

== 3. escape hatches (what new.env(parent = caller) does NOT stop) 
a. `counter <<- counter + 1` in the agent env -> caller$counter = 1 (MODIFIED) 
b. calling a caller-defined function with `<<-` -> caller$counter = 101 (MODIFIED) 
c. `cfg$level <- 2` on an environment object -> caller$cfg$level = 2 (MODIFIED: reference semantics) 
d. data.table `dt[, b := a * 10]` -> caller's dt columns: a,b (MODIFIED in place) 
e. assign(..., envir = globalenv()) -> exists('leak') in caller: TRUE (MODIFIED) 
f. `brand_new <<- 42` (name exists nowhere) -> created in globalenv: TRUE 
g. runif() in the agent changes globalenv's .Random.seed: TRUE (RNG state is process-global) 
h. rm(big) in the agent -> warning 'object 'big' not found'; caller keeps big: TRUE 

== 4. guard: lock the caller's bindings while agent code runs 
`counter <<- counter + 1` under the guard -> error: cannot change value of locked binding for 'counter' | caller$counter = 0 
`another_new <<- 1` under the guard -> not blocked (new binding) but detected: created = another_new 
`cfg$level <- 3` under the guard -> not blocked (value inside a reference object): caller$cfg$level = 3 
bindings are unlocked again afterwards: counter locked = FALSE 
guard overhead with 2026 bindings in the workspace: 79.7 ms per tool call 

== 5. two inline agents, separate overlays, explicit export with conflict policy 
a1 exports res -> res 
a2 exports res with conflict='error' -> export would overwrite `res` in the target environment 
a2 exports res with conflict='rename' -> res_a2 
caller now has: another_new,big,brand_new,bump,cfg,counter,dt,leak,res,res_a2
```
(Guard overhead was 51.0 ms on the previous run; both at load 50-110. §5.13 measures a leaner version.) The first run of this script, before the `tryCatch` around `lockBinding()`, failed with "Error in lockBinding(n, env) : bad binding access"; the isolated reproduction:
```
$ Rscript --vanilla -e 'for (i in 1:3) NULL; r1 <- tryCatch({lockBinding("i", globalenv()); "ok"}, error = function(e) conditionMessage(e)); cat(r1, "\n"); assign("i", get("i", globalenv()), globalenv()); cat(tryCatch({lockBinding("i", globalenv()); "ok"}, error = function(e) conditionMessage(e)), "\n")'
bad binding access 
ok 
```

### 5.6 Prototype (b): out-of-process round trips and 500 MB transfer (`p4_workers.R`, `p4b_transfer.R`)

`p4b_transfer.R` (run with `R_LIBS=<scratchpad>/rlib`):
```r
# p4b_transfer.R -- focused re-measurement of shipping ~500 MB to a worker (5 reps, median, min, max).
RLIB <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
.libPaths(c(RLIB, .libPaths()))                       # run with R_LIBS=RLIB so daemons find mirai too
suppressPackageStartupMessages({ library(mirai); library(mori) })
now <- function() as.numeric(Sys.time())
tm <- function(expr, reps = 5) { f <- substitute(expr); e <- parent.frame()
  v <- vapply(seq_len(reps), function(i) { invisible(gc()); t <- now(); eval(f, e); now() - t }, 0)
  sprintf("median %6.3f  min %6.3f  max %6.3f", median(v), min(v), max(v)) }
row <- function(k, v) cat(sprintf("%-60s %s\n", k, v))
x <- runif(6.5e7); cat(sprintf("x: %.0f MB | load: %s\n", as.numeric(object.size(x)) / 2^20, system("uptime", intern = TRUE)))
s <- callr::r_session$new()
daemons(1)                                            # one daemon (dispatcher on)
invisible(mirai(1)[])
row("serialize(x, NULL) (xdr)", tm(serialize(x, NULL)))
row("serialize(x, NULL, xdr = FALSE)", tm(serialize(x, NULL, xdr = FALSE)))
row("callr r_session$run(sum, list(x))", tm(s$run(function(x) sum(x), list(x))))
row("mirai(sum(x), x = x)[] (1 daemon, dispatcher)", tm(mirai(sum(x), x = x)[]))
daemons(0); daemons(1, dispatcher = FALSE); invisible(mirai(1)[])
row("mirai(sum(x), x = x)[] (1 daemon, no dispatcher)", tm(mirai(sum(x), x = x)[]))
if (.Platform$OS.type == "unix") row("mcparallel(sum(x)) + mccollect (fork)", tm({ j <- parallel::mcparallel(sum(x)); parallel::mccollect(j) }))
row("mori::share(x)", tm({ xs <- share(x) }, reps = 3))
xs <- share(x)
row("mirai(sum(xs), xs = xs)[] (shared memory)", tm(mirai(sum(xs), xs = xs)[]))
row("callr r_session$run(sum, list(xs)) (shared memory)", tm(s$run(function(x) { loadNamespace("mori"); sum(x) }, list(xs))))
row("sum(x) locally (baseline compute)", tm(sum(x)))
s$close(); daemons(0)
```
Output (`p4b_output.txt`):
```
x: 496 MB | load: 19:01  up 7 days, 15:29, 1 user, load averages: 22.03 33.56 41.49
serialize(x, NULL) (xdr)                                     median  0.639  min  0.591  max  0.739
serialize(x, NULL, xdr = FALSE)                              median  0.164  min  0.148  max  0.178
callr r_session$run(sum, list(x))                            median  1.381  min  1.298  max  1.539
mirai(sum(x), x = x)[] (1 daemon, dispatcher)                median  3.846  min  2.996  max  4.605
mirai(sum(x), x = x)[] (1 daemon, no dispatcher)             median  3.472  min  2.012  max  3.644
mcparallel(sum(x)) + mccollect (fork)                        median  0.233  min  0.210  max  0.240
mori::share(x)                                               median  0.169  min  0.134  max  0.246
mirai(sum(xs), xs = xs)[] (shared memory)                    median  0.329  min  0.262  max  0.515
callr r_session$run(sum, list(xs)) (shared memory)           median  0.334  min  0.235  max  0.392
sum(x) locally (baseline compute)                            median  0.189  min  0.168  max  0.215
```

`p4_workers.R` (start-up, round trips, mori coverage):
```r
# p4_workers.R -- PROTOTYPE (b): out-of-process workers. Startup latency, round trip, and the cost of
# shipping a ~500 MB object to a worker: callr::r_session, callr::r_bg, mirai daemons, parallel fork,
# future (multisession), and mori shared memory (with mirai and with callr). Medians of `reps` runs.
RLIB <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
.libPaths(c(RLIB, .libPaths()))
suppressPackageStartupMessages({ library(mirai); library(mori) })
now <- function() as.numeric(Sys.time())
tm <- function(expr, reps = 3) { f <- substitute(expr); e <- parent.frame()
  v <- vapply(seq_len(reps), function(i) { t <- now(); eval(f, e); now() - t }, 0); median(v) }
cat(sprintf("R %s | callr %s | processx %s | mirai %s | nanonext %s | mori %s | future %s | parallelly %s | cores %d | availableCores %d\n",
  getRversion(), packageVersion("callr"), packageVersion("processx"), packageVersion("mirai"), packageVersion("nanonext"),
  packageVersion("mori"), packageVersion("future"), packageVersion("parallelly"), parallel::detectCores(), parallelly::availableCores()))
res <- list(); add <- function(k, v) { res[[k]] <<- v; cat(sprintf("%-68s %8.3f s\n", k, v)) }

cat("\n## startup and trivial round trip\n")
add("callr::r_session$new() (wait = TRUE)", tm({ s <- callr::r_session$new(); s$close() }))
s <- callr::r_session$new()
add("r_session$run(function() 1) warm round trip", tm(s$run(function() 1), reps = 10))
add("callr::r_bg(function() 1) start + wait + get_result", tm({ p <- callr::r_bg(function() 1); p$wait(); p$get_result() }))
add("callr::r(function() 1) (blocking, new process)", tm(callr::r(function() 1)))
add("mirai::daemons(1) start (dispatcher = TRUE) + first mirai", tm({ daemons(1); m <- mirai(1); m[]; daemons(0) }))
add("mirai::daemons(4, dispatcher = FALSE) start + 4 mirai", tm({ daemons(4, dispatcher = FALSE); ms <- lapply(1:4, function(i) mirai(i)); lapply(ms, `[`); daemons(0) }))
daemons(2)
invisible(mirai(1)[])
add("mirai warm round trip mirai(1)[] (2 daemons)", tm(mirai(1)[], reps = 20))
add("mirai_map(1:8, function(i) i)[] warm", tm(mirai_map(1:8, function(i) i)[], reps = 5))
if (.Platform$OS.type == "unix") {
  add("parallel::mcparallel(1) + mccollect (fork)", tm({ j <- parallel::mcparallel(1); parallel::mccollect(j) }))
}
add("future multisession(2): plan + first value", tm({ future::plan(future::multisession, workers = 2); future::value(future::future(1)); future::plan(future::sequential) }))

cat("\n## shipping a ~500 MB object (x <- runif(6.5e7))\n")
x <- runif(6.5e7); mb <- as.numeric(object.size(x)) / 2^20
cat(sprintf("object: %.0f MB numeric\n", mb))
add("serialize(x, NULL) in the parent (xdr)", tm(serialize(x, NULL)))
add("serialize(x, NULL, xdr = FALSE) in the parent", tm(serialize(x, NULL, xdr = FALSE)))
f <- tempfile(fileext = ".rds")
add("saveRDS(x, compress = FALSE)", tm(saveRDS(x, f, compress = FALSE)))
add("callr r_session$run(function(x) sum(x), list(x)) warm session", tm(s$run(function(x) sum(x), list(x))))
add("callr::r_bg(function(x) sum(x), list(x)) incl. startup", tm({ p <- callr::r_bg(function(x) sum(x), list(x)); p$wait(); p$get_result() }))
add("mirai({sum(x)}, x = x)[] (2 daemons, dispatcher)", tm(mirai(sum(x), x = x)[]))
everywhere({}, x = x)          # also measure: broadcast once, then reuse without re-shipping
add("mirai everywhere(x = x) broadcast to 2 daemons (one-off)", tm(everywhere({ assign("xx", x, globalenv()) }, x = x)[]))
add("mirai(sum(xx))[] after broadcast", tm(mirai(sum(xx))[]))
if (.Platform$OS.type == "unix")
  add("mcparallel(sum(x)) + mccollect (fork, no copy)", tm({ j <- parallel::mcparallel(sum(x)); parallel::mccollect(j) }))

cat("\n## mori: one copy in shared memory, workers map it\n")
add("mori::share(x) (copy into shared memory, once)", tm({ xs <- share(x) }, reps = 1))
add("length(serialize(xs, NULL)) bytes", length(serialize(xs, NULL)))
add("sum(x) in parent, regular vector", tm(sum(x)))
add("sum(xs) in parent, shared ALTREP vector", tm(sum(xs)))
add("mirai(sum(xs), xs = xs)[] (shared)", tm(mirai(sum(xs), xs = xs)[]))
add("callr r_session$run(function(x) sum(x), list(xs)) (shared)", tm(s$run(function(x) { library(mori); sum(x) }, list(xs))))
chk <- s$run(function(x) { library(mori); list(shared = is_shared(x), sum = sum(x), vcells_mb = gc()[2, 2]) }, list(xs))
cat(sprintf("  child sees shared=%s, sum equal=%s, child R heap Vcells used %.1f MB (object is %.0f MB)\n",
  chk$shared, isTRUE(all.equal(chk$sum, sum(x))), chk$vcells_mb, mb))
chk2 <- s$run(function(x) list(vcells_mb = gc()[2, 2]), list(x))
cat(sprintf("  same check with the regular vector: child R heap Vcells used %.1f MB\n", chk2$vcells_mb))
w <- mirai({ xs[1:3] <- 0; list(shared_after_write = mori::is_shared(xs), head = xs[1:3]) }, xs = xs)[]
cat(sprintf("  worker writes xs[1:3] <- 0: still shared in worker = %s, worker head = %s, parent head = %s\n",
  w$shared_after_write, paste(round(w$head, 3), collapse = ","), paste(round(xs[1:3], 3), collapse = ",")))

cat("\n## mori object-type coverage\n")
df <- data.frame(a = runif(10), b = letters[1:10], f = factor(letters[1:10]))
cat("  data.frame shared:", is_shared(share(df)), "\n")
cat("  list(num, chr) shared:", is_shared(share(list(a = 1:3, b = "z"))), "\n")
cat("  environment shared:", is_shared(share(new.env())), "\n")
if (requireNamespace("Matrix", quietly = TRUE)) {
  m <- Matrix::rsparsematrix(1000, 1000, 0.01)
  cat("  S4 dgCMatrix shared:", is_shared(share(m)), "| its @x slot shared:", is_shared(share(m@x)), "\n")
}
setClass("Toy", representation(counts = "numeric", meta = "data.frame"))
toy <- new("Toy", counts = runif(10), meta = df)
cat("  user S4 object shared:", is_shared(share(toy)), "\n")
s$close(); daemons(0)
saveRDS(res, file.path(dirname(f), "p4_res.rds"))
```
Output (`p4_output.txt`, run with `R_LIBS` set; the line "length(serialize(xs, NULL)) bytes 134.000 s" is a formatting artefact: the value is 134 bytes):
```
R 4.4.3 | callr 3.7.6 | processx 3.8.6 | mirai 2.6.1 | nanonext 1.8.1 | mori 0.2.2 | future 1.70.0 | parallelly 1.46.1 | cores 8 | availableCores 8

## startup and trivial round trip
callr::r_session$new() (wait = TRUE)                                    0.253 s
r_session$run(function() 1) warm round trip                             0.029 s
callr::r_bg(function() 1) start + wait + get_result                     0.246 s
callr::r(function() 1) (blocking, new process)                          0.253 s
mirai::daemons(1) start (dispatcher = TRUE) + first mirai               0.890 s
mirai::daemons(4, dispatcher = FALSE) start + 4 mirai                   0.633 s
mirai warm round trip mirai(1)[] (2 daemons)                            0.000 s
mirai_map(1:8, function(i) i)[] warm                                    0.002 s
parallel::mcparallel(1) + mccollect (fork)                              0.007 s
future multisession(2): plan + first value                              0.606 s

## shipping a ~500 MB object (x <- runif(6.5e7))
object: 496 MB numeric
serialize(x, NULL) in the parent (xdr)                                  0.882 s
serialize(x, NULL, xdr = FALSE) in the parent                           0.340 s
saveRDS(x, compress = FALSE)                                            0.754 s
callr r_session$run(function(x) sum(x), list(x)) warm session           3.182 s
callr::r_bg(function(x) sum(x), list(x)) incl. startup                  3.911 s
mirai({sum(x)}, x = x)[] (2 daemons, dispatcher)                        4.622 s
mirai everywhere(x = x) broadcast to 2 daemons (one-off)               29.088 s
mirai(sum(xx))[] after broadcast                                        0.192 s
mcparallel(sum(x)) + mccollect (fork, no copy)                          0.300 s

## mori: one copy in shared memory, workers map it
mori::share(x) (copy into shared memory, once)                          0.144 s
length(serialize(xs, NULL)) bytes                                     134.000 s
sum(x) in parent, regular vector                                        0.185 s
sum(xs) in parent, shared ALTREP vector                                 0.179 s
mirai(sum(xs), xs = xs)[] (shared)                                      0.269 s
callr r_session$run(function(x) sum(x), list(xs)) (shared)              0.412 s
  child sees shared=TRUE, sum equal=TRUE, child R heap Vcells used 4.2 MB (object is 496 MB)
  same check with the regular vector: child R heap Vcells used 500.1 MB
  worker writes xs[1:3] <- 0: still shared in worker = FALSE, worker head = 0,0,0, parent head = 0.79,0.147,0.625

## mori object-type coverage
  data.frame shared: TRUE 
  list(num, chr) shared: TRUE 
  environment shared: FALSE 
  S4 dgCMatrix shared: FALSE | its @x slot shared: TRUE 
  user S4 object shared: FALSE 
Error while shutting down parallel: unable to terminate some child processes
```
The first attempt without `R_LIBS` printed the callr lines, then "Error in loadNamespace(x) : there is no package called 'mirai'" (from the dispatcher child) and "mirai: initial sync with dispatcher [10 secs elapsed]" ... "[590 secs elapsed]" until I stopped it; no mirai processes were left behind (executed `pgrep -fl mirai` -> nothing).

### 5.7 mori: S4 slot sharing and materialization (`p16b_debug.R`, `p16c_ops.R`, `p16g_materialise.R`)

`p16b_debug.R`:
```r
RLIB <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
.libPaths(c(RLIB, .libPaths())); suppressPackageStartupMessages({ library(Matrix); library(mori) })
set.seed(1); m <- rsparsematrix(20000, 5000, density = 0.05)
ms <- m; ms@x <- share(m@x); ms@i <- share(m@i); ms@p <- share(m@p)
for (s in c("i", "p", "x")) cat(sprintf("slot %s: type %s, shared %s, serialised %d bytes\n", s, typeof(slot(ms, s)), is_shared(slot(ms, s)), length(serialize(slot(ms, s), NULL))))
cat("whole object serialised:", length(serialize(ms, NULL)), "bytes\n")
iv <- share(1:10 + 0L); cat("share(integer) shared:", is_shared(iv), "| share(sample.int) shared:", is_shared(share(sample.int(1e6))), "\n")
s <- callr::r_session$new()
r <- s$run(function(v) { a <- mori::is_shared(v); list(before_any_use = a, sum = sum(v), heap = gc()[2, 2]) }, list(ms@x))
cat(sprintf("worker, bare shared double vector: shared=%s heap=%.1f MB\n", r$before_any_use, r$heap))
r <- s$run(function(m) list(shared_x = mori::is_shared(m@x), heap = gc()[2, 2]), list(ms))
cat(sprintf("worker, dgCMatrix with shared slots (Matrix not attached): shared @x=%s heap=%.1f MB\n", r$shared_x, r$heap))
s$close()
```
Output:
```
slot i: type integer, shared TRUE, serialised 137 bytes
slot p: type integer, shared TRUE, serialised 137 bytes
slot x: type double, shared TRUE, serialised 134 bytes
whole object serialised: 572 bytes
share(integer) shared: TRUE | share(sample.int) shared: TRUE 
worker, bare shared double vector: shared=TRUE heap=4.2 MB
worker, dgCMatrix with shared slots (Matrix not attached): shared @x=TRUE heap=4.2 MB
```
The recursive helper in `p16_mori_s4.R` (slot assignment inside a function on an argument) produced "serialised size now: 20020478 bytes" and "worker sees shared @x: FALSE | worker heap 75.5 MB", which led to this investigation.

`p16g_materialise.R`:
```r
# p16g: after each operation, does the shared vector still serialise as a ~134-byte reference?
RLIB <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
.libPaths(c(RLIB, .libPaths())); library(mori)
ops <- c("sum(v)", "mean(v)", "v * 2", "v[5]", "v[1:10]", "head(v)", "range(v)", "max(v)", "which.max(v)", "var(v)",
         "sort(v)[1]", "crossprod(v)", "cumsum(v)[1]", "is.na(v)[1]", "v > 0.5", "length(v)", "print(v[1:3])")
for (op in ops) {
  v <- share(runif(2e6)); h0 <- gc()[2, 2]; t <- system.time(invisible(capture.output(eval(parse(text = op)))))[["elapsed"]]
  cat(sprintf("%-14s serialises to %9d bytes afterwards | heap retained +%5.1f MB | %.3f s\n", op, length(serialize(v, NULL)), gc()[2, 2] - h0, t))
}
```
Output:
```
sum(v)         serialises to       134 bytes afterwards | heap retained +  0.0 MB | 0.009 s
mean(v)        serialises to       134 bytes afterwards | heap retained +  0.0 MB | 0.009 s
v * 2          serialises to       134 bytes afterwards | heap retained +  0.0 MB | 2.332 s
v[5]           serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.001 s
v[1:10]        serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.007 s
head(v)        serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.003 s
range(v)       serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.043 s
max(v)         serialises to       134 bytes afterwards | heap retained +  0.0 MB | 0.004 s
which.max(v)   serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.016 s
var(v)         serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.013 s
sort(v)[1]     serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.201 s
crossprod(v)   serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.014 s
cumsum(v)[1]   serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.018 s
is.na(v)[1]    serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.028 s
v > 0.5        serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.426 s
length(v)      serialises to       134 bytes afterwards | heap retained +  0.0 MB | 0.001 s
print(v[1:3])  serialises to  16000107 bytes afterwards | heap retained + 15.3 MB | 0.003 s
```
`p16c_ops.R` (same question inside a callr worker, 153 MB vector `vs` and dgCMatrix `ms` with shared slots, heap delta after each op): `sum(v)` 0.0, `mean(v)` 0.0, `v[1:10]` 152.5, `range(v)` 152.6, `quantile(v, .5)` 152.6, `var(v)` 152.5, `sort(v)[1]` 152.5, `v * 2` 0.0, `crossprod(v)` 152.5, `matrix(v, ncol = 100) %*% 1` 152.5, `Matrix::colSums(m)` 38.1, `m %*% vector` 57.2, `m[1:10, 1:10]` 57.2 MB; `is_shared()` TRUE throughout. Script:
```r
RLIB <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"
.libPaths(c(RLIB, .libPaths())); suppressPackageStartupMessages({ library(Matrix); library(mori) })
set.seed(1); v <- runif(2e7); vs <- share(v)                      # 153 MB
m <- rsparsematrix(20000, 5000, density = 0.05); ms <- m; ms@x <- share(m@x); ms@i <- share(m@i); ms@p <- share(m@p)
s <- callr::r_session$new()
ops <- list(
  "sum(v)" = quote(sum(v)), "mean(v)" = quote(mean(v)), "v[1:10]" = quote(v[1:10]), "range(v)" = quote(range(v)),
  "quantile(v, .5)" = quote(stats::quantile(v, .5)), "var(v)" = quote(stats::var(v)), "sort(v)[1]" = quote(sort(v)[1]),
  "v * 2 (new vector)" = quote(v * 2), "crossprod(v)" = quote(crossprod(v)), "matrix(v, ncol = 100) %*% 1" = quote(matrix(v, ncol = 100) %*% rep(1, 100)),
  "Matrix::colSums(m)" = quote(Matrix::colSums(m)), "m %*% vector" = quote(m %*% rep(1, ncol(m))), "m[1:10, 1:10]" = quote(m[1:10, 1:10]))
for (nm in names(ops)) {
  r <- s$run(function(v, m, e) {
    suppressPackageStartupMessages(library(Matrix)); g0 <- gc()[2, 2]
    invisible(eval(e)); list(v_shared = mori::is_shared(v), m_shared = mori::is_shared(m@x), heap_delta = gc()[2, 2] - g0)
  }, list(vs, ms, ops[[nm]]))
  cat(sprintf("%-30s v still shared: %-5s  m@x still shared: %-5s  heap delta %7.1f MB\n", nm, r$v_shared, r$m_shared, r$heap_delta))
}
s$close()
```
`p16e_steps.R` showed that `.Internal(inspect())` also materializes (a vector that serialized to 134 bytes serialized to 160000107 bytes after one `inspect`).

### 5.8 Fork with live HTTP streams (`p11_fork_curl.R`)

```r
# p11_fork_curl.R -- fork (mcparallel) while the parent has live curl streams; child uses a fresh handle.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/15"
source(file.path(W, "mock_sse_base.R")); srv <- start_mock_sse()
pool <- curl::new_pool(host_con = 100); got <- 0L; fin <- FALSE
h <- curl::new_handle(url = sprintf("%s/sse?id=P&n=20&delay=0.05", srv$url), pipewait = 0L)
curl::multi_add(h, pool = pool, data = function(b, final = FALSE) got <<- got + lengths(regmatches(rawToChar(b), gregexpr("event: token", rawToChar(b)))),
                done = function(r) fin <<- TRUE)
curl::multi_run(timeout = 0.3, pool = pool)
big <- runif(2e7)
t <- system.time({
  jobs <- lapply(1:3, function(i) parallel::mcparallel({
    r <- curl::curl_fetch_memory(paste0(srv$url, "/ping"))          # fresh handle in the child
    list(pid = Sys.getpid(), ping = rawToChar(r$content), s = sum(big), same_obj = TRUE)
  }))
  res <- parallel::mccollect(jobs)
})[["elapsed"]]
while (!fin) curl::multi_run(timeout = 0.1, pool = pool)
cat(sprintf("3 forked children: %s | sums ok: %s | %.2fs\n", paste(vapply(res, `[[`, "", "ping"), collapse = ","),
            all(vapply(res, function(r) isTRUE(all.equal(r$s, sum(big))), NA)), t))
cat(sprintf("parent stream after the forks: %d/20 tokens, completed: %s\n", got, fin))
srv$stop()
```
Output: `3 forked children: pong,pong,pong | sums ok: TRUE | 0.13s` / `parent stream after the forks: 20/20 tokens, completed: TRUE`. Also executed: `parallelly::supportsMulticore()` -> TRUE; with `RSTUDIO=1` -> FALSE; with `_R_CHECK_LIMIT_CORES_=TRUE` `availableCores()` -> 2; `options(mc.cores = 3)` -> 3.

### 5.9 One reactor for inline, worker and CLI agents (`p10_mixed.R`)

```r
# p10_mixed.R -- one reactor for all three sub-agent modes at once:
#   inline : HTTP stream consumed in this process (curl multi, data callback)
#   worker : callr::r_bg child that does its own HTTP streaming and reports JSONL events on stdout
#   cli    : an external process (fake CLI) printing JSONL
# A single processx::poll() waits on curl's sockets AND the children's stdout pipes.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/15"
source(file.path(W, "mock_sse_base.R")); source(file.path(W, "sse.R"))
now <- function() as.numeric(Sys.time())
srv <- start_mock_sse(); t0 <- now()
events <- data.frame(t = numeric(), agent = character(), what = character(), stringsAsFactors = FALSE)
log_ev <- function(agent, what) events[nrow(events) + 1L, ] <<- list(round(now() - t0, 2), agent, what)

# inline agents
pool <- curl::new_pool(host_con = 100); done_inline <- c(in1 = FALSE, in2 = FALSE)
for (nm in names(done_inline)) local({ id <- nm; p <- sse_parser()
  h <- curl::new_handle(url = sprintf("%s/sse?id=%s&n=10&delay=0.15", srv$url, id), pipewait = 0L)
  curl::multi_add(h, pool = pool, data = function(b, final = FALSE) for (ev in p$feed(b, final)) if (ev$event == "token") log_ev(id, "token"),
                  done = function(r) { done_inline[[id]] <<- TRUE; log_ev(id, "done") })
})
# worker agents: the child streams from the provider itself and emits one JSON line per event
worker_fn <- function(url, id) {
  emit <- function(x) { cat(jsonlite::toJSON(x, auto_unbox = TRUE), "\n", sep = ""); flush(stdout()) }
  emit(list(type = "start", id = id, pid = Sys.getpid()))
  n <- 0L
  curl::curl_fetch_stream(sprintf("%s/sse?id=%s&n=10&delay=0.12", url, id), function(b) {
    k <- lengths(regmatches(rawToChar(b), gregexpr("event: token", rawToChar(b)))); n <<- n + k
    if (k) emit(list(type = "token", id = id, n = n)) }, handle = curl::new_handle(pipewait = 0L))
  emit(list(type = "result", id = id, text = sprintf("%s finished after %d tokens", id, n)))
  invisible(n)
}
procs <- list(
  wk1 = callr::r_bg(worker_fn, list(url = srv$url, id = "wk1"), stdout = "|", supervise = TRUE, cleanup_tree = TRUE),
  wk2 = callr::r_bg(worker_fn, list(url = srv$url, id = "wk2"), stdout = "|", supervise = TRUE, cleanup_tree = TRUE),
  cli = processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e",
          "for (i in 1:6) { Sys.sleep(0.25); cat(sprintf('{\"type\":\"assistant\",\"i\":%d}\\n', i)); flush(stdout()) }; cat('{\"type\":\"result\",\"result\":\"cli ok\"}\\n')"),
          stdout = "|", supervise = TRUE, cleanup_tree = TRUE))
partial <- setNames(rep("", length(procs)), names(procs)); iters <- 0L
repeat {
  alive <- names(procs)[vapply(procs, function(p) p$is_alive() || p$is_incomplete_output(), NA)]
  if (all(done_inline) && !length(alive)) break
  fds <- curl::multi_fdset(pool = pool)
  pollables <- c(list(curl = processx::curl_fds(fds)), procs[alive])
  processx::poll(pollables, 250L); iters <- iters + 1L
  curl::multi_run(timeout = 0, pool = pool)                            # inline callbacks fire here
  for (nm in alive) {
    out <- procs[[nm]]$read_output(); if (!nzchar(out)) next
    buf <- paste0(partial[[nm]], out); lines <- strsplit(buf, "\n", fixed = TRUE)[[1]]
    if (!endsWith(buf, "\n")) { partial[[nm]] <- lines[length(lines)]; lines <- lines[-length(lines)] } else partial[[nm]] <- ""
    for (ln in lines) { ev <- tryCatch(jsonlite::fromJSON(ln), error = function(e) NULL); if (!is.null(ev)) log_ev(nm, ev$type) }
  }
}
wall <- now() - t0
tab <- table(events$agent, events$what); print(tab)
ord <- events$agent[events$what %in% c("token", "assistant")]
cat(sprintf("\nWALL %.2fs for 2 inline (1.65 s each) + 2 worker (1.3 s + R startup) + 1 cli (1.5 s + R startup) | poll iterations %d | source switches in arrival order %d\n",
  wall, iters, sum(ord[-1] != ord[-length(ord)])))
cat("first 30 arrivals:", paste(sprintf("%.2f:%s", head(events$t, 30), head(events$agent, 30)), collapse = " "), "\n")
cat("worker results:", paste(vapply(procs[c("wk1", "wk2")], function(p) p$get_result(), 1L), collapse = ","), "\n")
srv$stop()
```
Output:
```
      assistant done result start token
  cli         6    0      1     0     0
  in1         0    1      0     0    10
  in2         0    1      0     0    10
  wk1         0    0      1     1    10
  wk2         0    0      1     1    10

WALL 2.08s for 2 inline (1.65 s each) + 2 worker (1.3 s + R startup) + 1 cli (1.5 s + R startup) | poll iterations 55 | source switches in arrival order 45
first 30 arrivals: 0.45:wk1 0.45:wk2 0.56:wk1 0.57:wk2 0.57:in1 0.58:in2 0.65:cli 0.68:wk1 0.69:wk2 0.72:in1 0.73:in2 0.80:wk1 0.81:wk2 0.87:in1 0.88:in2 0.90:cli 0.92:wk1 0.93:wk2 1.03:in1 1.03:in2 1.04:wk1 1.05:wk2 1.16:cli 1.16:wk1 1.17:wk2 1.17:in1 1.18:in2 1.28:wk1 1.29:wk2 1.32:in1 
worker results: 10,10 
```

### 5.10 Prototype (d): interrupt cleanup (`p6_session.R`, `p6_interrupt.R`)

`p6_session.R`:
```r
# p6_session.R -- the "user's R session" for the interrupt demo. Usage: Rscript p6_session.R <mock-url> <mode>
# mode "graceful": waits in the reactor; the harness sends SIGINT; the interrupt handler + on.exit clean up.
# mode "hard": same setup, the harness SIGKILLs this process (no R code can run); only processx's
#              supervisor can clean up, so one worker is started WITHOUT supervise to show the difference.
args <- commandArgs(TRUE); url <- args[1]; mode <- args[2]
now <- function() as.numeric(Sys.time())
emit <- function(...) { cat(..., "\n", sep = ""); flush(stdout()) }

run_agents <- function() {
  pool <- curl::new_pool(host_con = 100)
  procs <- list(); handles <- list(); t_int <- NA
  cleanup <- function() {                      # idempotent; runs on interrupt, error, or normal exit
    t0 <- now()
    for (h in handles) try(curl::multi_cancel(h), silent = TRUE)
    killed <- unlist(lapply(procs, function(p) tryCatch(p$kill_tree(), error = function(e) integer())))
    emit(sprintf("CLEANUP cancelled %d transfers, kill_tree() killed pids [%s] in %.0f ms",
                 length(handles), paste(killed, collapse = ","), 1000 * (now() - t0)))
  }
  on.exit(cleanup(), add = TRUE)
  # 3 worker R processes (sub-agents in "worker" mode), each doing 300 s of "work"
  for (i in 1:3) procs[[paste0("worker", i)]] <- callr::r_bg(function() { Sys.sleep(300); "never" },
    supervise = (mode == "graceful" || i != 3), cleanup_tree = TRUE)
  # 2 external CLI-like processes (stand-ins for `claude -p` / `codex exec`) that spawn a grandchild
  rs <- file.path(R.home("bin"), "Rscript")
  for (i in 1:2) procs[[paste0("cli", i)]] <- processx::process$new(rs,
    c("-e", "p <- processx::process$new(file.path(R.home('bin'),'Rscript'), c('-e','Sys.sleep(300)')); Sys.sleep(300)"),
    supervise = TRUE, cleanup_tree = TRUE, stdout = "|")
  # 4 long SSE streams (inline sub-agents talking to a provider)
  got <- integer(4)
  for (i in 1:4) local({ k <- i
    h <- curl::new_handle(url = sprintf("%s/sse?id=S%d&n=3000&delay=0.1", url, k), pipewait = 0L)
    handles[[k]] <<- h
    curl::multi_add(h, pool = pool, data = function(b, final = FALSE) got[k] <<- got[k] + 1L)
  })
  Sys.sleep(1)  # let the grandchildren start
  pids <- vapply(procs, function(p) p$get_pid(), 1L)
  grand <- unlist(lapply(procs[grep("^cli", names(procs))], function(p) {
    ch <- ps::ps_children(ps::ps_handle(p$get_pid())); vapply(ch, ps::ps_pid, 1L) }))
  emit("PIDS ", paste(c(pids, grand), collapse = ","))
  emit("SUPERVISED ", paste(vapply(procs, function(p) p$is_supervised(), NA), collapse = ","))
  repeat {                                     # the reactor: waits on HTTP sockets and child pipes together
    fds <- curl::multi_fdset(pool = pool)
    processx::poll(c(list(processx::curl_fds(fds)), procs[grep("^cli", names(procs))]), 1000L)
    curl::multi_run(timeout = 0, pool = pool)
    if (sum(got) > 20 && !exists("said", inherits = FALSE)) { said <- TRUE; emit("STREAMING chunks=", sum(got)) }
  }
}

res <- tryCatch(run_agents(), interrupt = function(e) {
  emit(sprintf("INTERRUPT caught at %.3f (class: %s)", now(), paste(class(e), collapse = "/")))
  structure("aborted", class = "gptr_aborted")
})
emit("RESULT ", class(res)[1])
```
`p6_interrupt.R`:
```r
# p6_interrupt.R -- PROTOTYPE (d) harness: start a session that owns 3 workers, 2 CLI processes (each with a
# grandchild) and 4 streaming HTTP transfers; interrupt it (SIGINT = Ctrl-C), then check every pid.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/15"
source(file.path(W, "mock_sse_base.R"))
now <- function() as.numeric(Sys.time())
alive <- function(pid) tryCatch(ps::ps_is_running(ps::ps_handle(as.integer(pid))), error = function(e) FALSE)
srv <- start_mock_sse()

run_case <- function(mode) {
  cat(sprintf("\n==== mode = %s\n", mode))
  s <- processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", file.path(W, "p6_session.R"), srv$url, mode),
                             stdout = "|", stderr = "2>&1")
  lines <- character(); pids <- integer()
  deadline <- now() + 60
  while (now() < deadline && !any(grepl("^STREAMING", lines))) {
    processx::poll(list(s), 500L); new <- s$read_output_lines(); lines <- c(lines, new)
  }
  pids <- as.integer(strsplit(sub("^PIDS ", "", grep("^PIDS", lines, value = TRUE)), ",")[[1]])
  cat(paste0("  session> ", lines), sep = "\n")
  cat(sprintf("  before: %d child/grandchild pids alive: %s\n", sum(vapply(pids, alive, NA)), paste(pids, collapse = ",")))
  t0 <- now()
  if (mode == "graceful") s$interrupt() else s$kill()      # SIGINT (Ctrl-C) vs SIGKILL (crash / force quit)
  s$wait(10000)
  t_exit <- now() - t0
  rest <- tryCatch(s$read_all_output_lines(), error = function(e) "(pipe closed by kill(): no output after SIGKILL)")
  cat(paste0("  session> ", rest), sep = "\n")
  deadline <- now() + 5
  while (now() < deadline && any(vapply(pids, alive, NA))) Sys.sleep(0.1)
  still <- pids[vapply(pids, alive, NA)]
  cat(sprintf("  session exited %.2fs after the signal (exit status %s); still alive after 5 s: %s\n", t_exit,
              format(s$get_exit_status()), if (length(still)) paste(still, collapse = ",") else "none"))
  for (p in still) try(ps::ps_kill(ps::ps_handle(p)), silent = TRUE)   # tidy up the demo's orphans
  invisible(still)
}
run_case("graceful")
run_case("hard")
srv$stop()
```
Output (`p6_output.txt`):
```
==== mode = graceful
  session> PIDS 11866,11874,11876,11880,11888,11921,11920
  session> SUPERVISED TRUE,TRUE,TRUE,TRUE,TRUE
  session> STREAMING chunks=21
  before: 7 child/grandchild pids alive: 11866,11874,11876,11880,11888,11921,11920
  session> CLEANUP cancelled 4 transfers, kill_tree() killed pids [11866,11874,11876,11880,11921,11888,11920] in 190 ms
  session> INTERRUPT caught at 1790733459.231 (class: interrupt/condition)
  session> RESULT gptr_aborted
  session exited 0.41s after the signal (exit status 0); still alive after 5 s: none

==== mode = hard
  session> PIDS 12497,12505,12509,12512,12514,12544,12560
  session> SUPERVISED TRUE,TRUE,FALSE,TRUE,TRUE
  session> STREAMING chunks=22
  before: 7 child/grandchild pids alive: 12497,12505,12509,12512,12514,12544,12560
  session> (pipe closed by kill(): no output after SIGKILL)
  session exited 0.00s after the signal (exit status -9); still alive after 5 s: 12509,12544,12560
```
(An earlier run of the graceful case: "killed ... in 253 ms", exit 0.51 s. An earlier crashed harness run left 3 orphans, which I identified with `ps -o pid=,command=` as this demo's `callr-scr-*` worker and two `R ... -e Sys.sleep(300)` grandchildren, and killed.) Note that `on.exit()` cleanup ran before the `interrupt` handler: `tryCatch` unwinds first.

`p12_interrupt_latency.R`:
```r
# p12_interrupt_latency.R -- how quickly does SIGINT (Ctrl-C) surface as an R `interrupt` condition while the
# session is blocked in each wait primitive a gptr reactor could use? Each case runs in a fresh Rscript child.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/15"
source(file.path(W, "mock_sse_base.R")); srv <- start_mock_sse()
now <- function() as.numeric(Sys.time())
cases <- list(
  "Sys.sleep(30)" = "Sys.sleep(30)",
  "curl::multi_run(timeout = 30) on a slow stream" = sprintf("pool <- curl::new_pool(); curl::multi_add(curl::new_handle(url = '%s/sse?n=1000&delay=5', pipewait = 0L), pool = pool, data = function(b, final = FALSE) NULL); curl::multi_run(timeout = 30, pool = pool)", srv$url),
  "curl::curl_fetch_memory() blocking on a slow response" = sprintf("curl::curl_fetch_memory('%s/sse?n=1000&delay=5')", srv$url),
  "httr2 resp_stream_sse(blocking) on a slow stream" = sprintf("r <- httr2::req_perform_connection(httr2::request('%s/sse?n=1000&delay=5')); httr2::resp_stream_sse(r)", srv$url),
  "processx::poll(list(p), 30000) on a silent child" = "p <- processx::process$new(file.path(R.home('bin'), 'Rscript'), c('-e', 'Sys.sleep(60)'), stdout = '|', cleanup_tree = TRUE); processx::poll(list(p), 30000L)",
  "callr r_session$run(Sys.sleep(30))" = "s <- callr::r_session$new(); s$run(function() Sys.sleep(30))",
  "mirai: m[] waiting on a 30 s task" = "library(mirai); daemons(1); m <- mirai(Sys.sleep(30)); m[]",
  "pure R loop (tool code): repeat x <- sqrt(runif(1e5))" = "repeat x <- sqrt(runif(1e5))",
  "later::run_now(timeoutSecs = 30)" = "later::later(function() NULL, 60); later::run_now(timeoutSecs = 30)"
)
for (nm in names(cases)) {
  code <- sprintf("t_start <- NA; tryCatch({ cat('READY\\n'); flush(stdout()); %s }, interrupt = function(e) { cat(sprintf('CAUGHT %%.3f\\n', as.numeric(Sys.time()))); flush(stdout()) }); cat('AFTER\\n')", cases[[nm]])
  f <- tempfile(fileext = ".R"); writeLines(code, f)
  p <- processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", f), stdout = "|", stderr = "|",
                             env = c("current", R_LIBS = "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"), cleanup_tree = TRUE)
  out <- ""; t_dead <- now() + 30
  while (!grepl("READY", out) && now() < t_dead) { processx::poll(list(p), 200L); out <- paste0(out, p$read_output()) }
  Sys.sleep(1.5)                                     # let it block
  t_sig <- now(); p$interrupt()
  while (p$is_alive() && now() - t_sig < 12) { processx::poll(list(p), 100L); out <- paste0(out, p$read_output()) }
  out <- paste0(out, tryCatch(p$read_all_output(), error = function(e) ""))
  caught <- regmatches(out, regexpr("CAUGHT [0-9.]+", out))
  lat <- if (length(caught)) sprintf("%.3f s", as.numeric(sub("CAUGHT ", "", caught)) - t_sig) else "NOT caught"
  status <- if (p$is_alive()) { p$kill_tree(); "still running after 12 s (killed)" } else sprintf("exited (status %s), AFTER printed: %s", p$get_exit_status(), grepl("AFTER", out))
  cat(sprintf("%-58s latency %-11s %s\n", nm, lat, status))
}
srv$stop()
```
Output:
```
Sys.sleep(30)                                              latency 0.007 s     exited (status 0), AFTER printed: TRUE
curl::multi_run(timeout = 30) on a slow stream             latency 0.000 s     exited (status 0), AFTER printed: TRUE
curl::curl_fetch_memory() blocking on a slow response      latency 0.001 s     exited (status 0), AFTER printed: TRUE
httr2 resp_stream_sse(blocking) on a slow stream           latency 0.009 s     exited (status 0), AFTER printed: TRUE
processx::poll(list(p), 30000) on a silent child           latency 0.202 s     exited (status 0), AFTER printed: TRUE
callr r_session$run(Sys.sleep(30))                         latency 0.258 s     exited (status 0), AFTER printed: TRUE
mirai: m[] waiting on a 30 s task                          latency 0.292 s     exited (status 0), AFTER printed: TRUE
pure R loop (tool code): repeat x <- sqrt(runif(1e5))      latency 0.046 s     exited (status 0), AFTER printed: TRUE
later::run_now(timeoutSecs = 30)                           latency 0.000 s     exited (status 0), AFTER printed: TRUE
```

### 5.11 Console progress renderer (`p9_progress.R`)

```r
# p9_progress.R -- console progress for several concurrent agents.
# One status line, redrawn in place with \r when cli::is_dynamic_tty() (terminal, RStudio, R.app, RKWard);
# otherwise (knitr, Rscript > file, Jupyter) only start/finish/tool event lines are printed.
status_renderer <- function(stream = stderr(), min_interval = 0.1) {
  dynamic <- cli::is_dynamic_tty(stream); last <- 0; last_width <- 0L
  spin <- c("-", "\\", "|", "/"); k <- 0L
  line_for <- function(agents) {
    parts <- vapply(agents, function(a) switch(a$state,
      streaming = sprintf("%s %s %d tok", a$name, spin[k %% 4 + 1], a$tokens),
      tool      = sprintf("%s running %s", a$name, a$tool),
      done      = sprintf("%s done", a$name),
      error     = sprintf("%s FAILED", a$name),
      queued    = sprintf("%s queued", a$name)), "")
    n_done <- sum(vapply(agents, function(a) a$state %in% c("done", "error"), NA))
    sprintf("[%d/%d] %s", n_done, length(agents), paste(parts, collapse = " | "))
  }
  list(
    dynamic = dynamic,
    update = function(agents, force = FALSE) {
      if (!dynamic) return(invisible())
      t <- as.numeric(Sys.time()); if (!force && t - last < min_interval) return(invisible())
      last <<- t; k <<- k + 1L
      txt <- cli::ansi_strtrim(line_for(agents), cli::console_width() - 1L)
      pad <- max(0L, last_width - cli::ansi_nchar(txt)); last_width <<- cli::ansi_nchar(txt)
      cat("\r", txt, strrep(" ", pad), sep = "", file = stream)
    },
    event = function(msg) {                         # permanent lines (tool calls, completions)
      if (dynamic) cat("\r", strrep(" ", last_width), "\r", sep = "", file = stream)
      cat(msg, "\n", sep = "", file = stream)
      last_width <<- 0L
    },
    finish = function() if (dynamic) cat("\r", strrep(" ", last_width), "\r", sep = "", file = stream)
  )
}

agents <- lapply(c("stats", "code", "biology"), function(n) { e <- new.env(); e$name <- n; e$state <- "streaming"; e$tokens <- 0L; e$tool <- ""; e })
r <- status_renderer()
cat(sprintf("dynamic tty: %s | console width %d\n", r$dynamic, cli::console_width()), file = stderr())
for (step in 1:30) {
  for (a in agents) if (a$state == "streaming") a$tokens <- a$tokens + sample(1:5, 1)
  if (step == 8)  { agents[[2]]$state <- "tool"; agents[[2]]$tool <- "r: summary(fit)"; r$event("code: tool r  summary(fit)") }
  if (step == 14) { agents[[2]]$state <- "streaming" }
  if (step == 20) { agents[[1]]$state <- "done"; r$event("stats: done (412 tokens, 2 turns)") }
  if (step == 27) { agents[[3]]$state <- "error"; r$event("biology: FAILED (HTTP 529 overloaded)") }
  r$update(agents)
  Sys.sleep(0.05)
}
r$finish()
cat("all agents finished\n", file = stderr())
```
Output piped (non-dynamic): `dynamic tty: FALSE | console width 80`, then only `code: tool r  summary(fit)`, `stats: done (412 tokens, 2 turns)`, `biology: FAILED (HTTP 529 overloaded)`, `all agents finished`. With `R_CLI_DYNAMIC=true` (carriage returns shown as `<CR>`, excerpt):
```
<CR>[0/3] stats \ 2 tok | code \ 4 tok | biology \ 3 tok<CR>[0/3] stats | 4 tok | code | 12 tok | biology | 10 tok ... <CR>code: tool r  summary(fit)
<CR>[0/3] stats \ 21 tok | code running r: summary(fit) | biology \ 24 tok ... <CR>stats: done (412 tokens, 2 turns)
<CR>[1/3] stats done | code / 54 tok | biology / 58 tok ... <CR>biology: FAILED (HTTP 529 overloaded)
<CR>[2/3] stats done | code | 70 tok | biology FAILED ... <CR>all agents finished
```
(`script -q /dev/null` could not allocate a pseudo-terminal in this sandbox: "tcgetattr/ioctl: Operation not supported on socket".)

### 5.12 Per-agent RNG streams (`p14_rng.R`)

```r
# p14_rng.R -- give each inline agent its own reproducible RNG stream (L'Ecuyer-CMRG), swapped in around
# each tool evaluation, so interleaved agents neither disturb each other nor the user's RNG state.
with_agent_rng <- function(agent, expr) {
  g <- globalenv(); had <- exists(".Random.seed", g, inherits = FALSE)
  user_seed <- if (had) get(".Random.seed", g) ; user_kind <- RNGkind()
  on.exit({ agent$seed <- get(".Random.seed", g)                       # save the agent's advanced state
            do.call(RNGkind, as.list(user_kind))
            if (had) assign(".Random.seed", user_seed, g) else rm(".Random.seed", envir = g) }, add = TRUE)
  RNGkind("L'Ecuyer-CMRG"); assign(".Random.seed", agent$seed, g)
  expr
}
new_agent_rng <- function(n, seed) {                                     # n independent streams from one seed
  g <- globalenv(); had <- exists(".Random.seed", g, inherits = FALSE)
  user_seed <- if (had) get(".Random.seed", g); user_kind <- RNGkind()
  on.exit({ do.call(RNGkind, as.list(user_kind))                       # restore the user's RNG exactly
            if (had) assign(".Random.seed", user_seed, g) else rm(".Random.seed", envir = g) }, add = TRUE)
  set.seed(seed, kind = "L'Ecuyer-CMRG"); s <- get(".Random.seed", g)
  out <- vector("list", n); for (i in seq_len(n)) { e <- new.env(); e$seed <- s; out[[i]] <- e; s <- parallel::nextRNGStream(s) }
  out
}
set.seed(1); user_ref <- runif(2); set.seed(1); user_before <- runif(1)
ag <- new_agent_rng(2, seed = 42)
# interleaved: A, B, A, B  vs  sequential: A, A, B, B -> each agent must get the same numbers either way
i1 <- c(A1 = with_agent_rng(ag[[1]], runif(1)), B1 = with_agent_rng(ag[[2]], runif(1)),
        A2 = with_agent_rng(ag[[1]], runif(1)), B2 = with_agent_rng(ag[[2]], runif(1)))
user_after <- runif(1)   # must equal user_ref[2]: agent draws in between must not consume the user stream
ag <- new_agent_rng(2, seed = 42)
s1 <- c(A1 = with_agent_rng(ag[[1]], runif(1)), A2 = with_agent_rng(ag[[1]], runif(1)),
        B1 = with_agent_rng(ag[[2]], runif(1)), B2 = with_agent_rng(ag[[2]], runif(1)))
cat("interleaved:", round(i1[c("A1","A2","B1","B2")], 6), "\nsequential: ", round(s1[c("A1","A2","B1","B2")], 6), "\n")
cat("same per-agent numbers regardless of interleaving:", identical(i1[c("A1","A2","B1","B2")], s1[c("A1","A2","B1","B2")]), "\n")
cat("user's RNG stream undisturbed by agent draws:", identical(c(user_before, user_after), user_ref), "| user RNGkind still:", RNGkind()[1], "\n")
```
Output:
```
interleaved: 0.173846 0.55474 0.8685 0.101751 
sequential:  0.173846 0.55474 0.8685 0.101751 
same per-agent numbers regardless of interleaving: TRUE 
user's RNG stream undisturbed by agent draws: TRUE | user RNGkind still: Mersenne-Twister 
```
(The first version of `new_agent_rng()` did not restore the user's seed and the last check printed FALSE; fixed as shown.)

### 5.13 Guard cost (`p15_guard_bench.R`)

```r
# p15_guard_bench.R -- cost of the binding-lock guard, naive vs lean implementation
env <- globalenv(); for (i in 1:2000) assign(sprintf("obj%04d", i), i, env); for (k in 1:3) NULL
guard_naive <- function(env, expr) {
  nms <- ls(env, all.names = TRUE); newly <- nms[!vapply(nms, bindingIsLocked, NA, env = env)]
  for (n in newly) tryCatch(lockBinding(n, env), error = function(e) { assign(n, get(n, envir = env), envir = env); lockBinding(n, env) })
  on.exit(for (n in newly) if (exists(n, envir = env, inherits = FALSE)) unlockBinding(n, env), add = TRUE)
  val <- expr; list(value = val, created = setdiff(ls(env, all.names = TRUE), nms))
}
guard_lean <- function(env, expr) {
  nms <- ls(env, all.names = TRUE, sorted = FALSE)
  locked <- vapply(nms, bindingIsLocked, NA, env = env, USE.NAMES = FALSE); newly <- nms[!locked]
  ok <- vapply(newly, function(n) !inherits(try(lockBinding(n, env), silent = TRUE), "try-error"), NA, USE.NAMES = FALSE)
  for (n in newly[!ok]) { assign(n, get(n, envir = env), envir = env); lockBinding(n, env) }   # immediate (unboxed) bindings
  on.exit(for (n in newly) unlockBinding(n, env), add = TRUE)
  val <- expr; after <- ls(env, all.names = TRUE, sorted = FALSE)
  list(value = val, created = after[!after %in% nms])
}
agent <- new.env(parent = env)
f <- function(g) g(env, eval(quote(1 + 1), agent))
print(bench::mark(naive = f(guard_naive), lean = f(guard_lean), iterations = 50, check = FALSE)[, c("expression", "min", "median", "mem_alloc")])
cat("bindings:", length(ls(env)), "| load:", system("uptime", intern = TRUE), "\n")
```
Output: `naive 26.3ms (min) 32.7ms (median) 253KB`, `lean 19.4ms 25.8ms 262KB`; `bindings: 2007 | load: ... load averages: 102.21 58.93 49.03`.

### 5.14 Background agent at an idle console (`p13_background_console.R`)

```r
# p13_background_console.R -- can an agent keep streaming in the background while the user is at the prompt?
# Drives an INTERACTIVE R (R --interactive, stdin piped) like a user would. The "agent" is a curl pool
# serviced by later::later_fd() (httr2's req_perform_promise uses the same mechanism). Between user
# commands the console is idle; later's input handler should run the callbacks.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/15"
source(file.path(W, "mock_sse_base.R")); srv <- start_mock_sse()
r <- processx::process$new(file.path(R.home("bin"), "R"), c("--interactive", "--vanilla", "--no-echo"),
                           stdin = "|", stdout = "|", stderr = "2>&1")
send <- function(code) r$write_input(paste0(code, "\n"))
read_for <- function(secs) { out <- ""; t <- Sys.time(); while (as.numeric(Sys.time() - t, units = "secs") < secs) {
  processx::poll(list(r), 100L); out <- paste0(out, r$read_output()) }; out }
send(sprintf(r"(
bg <- new.env(); bg$tokens <- 0L; bg$done <- FALSE
pool <- curl::new_pool()
curl::multi_add(curl::new_handle(url = "%s/sse?id=BG&n=30&delay=0.1", pipewait = 0L), pool = pool,
  data = function(b, final = FALSE) bg$tokens <- bg$tokens + lengths(regmatches(rawToChar(b), gregexpr("event: token", rawToChar(b)))),
  done = function(res) bg$done <- TRUE)
service <- function(ready = NULL) {          # re-arm on curl's sockets until the transfer completes
  curl::multi_run(timeout = 0, pool = pool)
  fd <- curl::multi_fdset(pool = pool)
  if (!bg$done) later::later_fd(service, fd$reads, fd$writes, fd$exceptions, timeout = max(fd$timeout, 0.05))
}
service()
cat("started; tokens so far:", bg$tokens, "\n")
)", srv$url))
o1 <- read_for(1.0)
send('cat("user command 1 at the prompt; tokens so far:", bg$tokens, "\\n")')
o2 <- read_for(1.2)
send('x <- summary(rnorm(1e6)); cat("user command 2; tokens so far:", bg$tokens, "done:", bg$done, "\\n")')
o3 <- read_for(2.0)
send('cat("user command 3; tokens so far:", bg$tokens, "done:", bg$done, "\\n")')
o4 <- read_for(0.8)
cat(gsub("\n+", "\n", paste(o1, o2, o3, o4)))
send("q('no')"); r$wait(3000); if (r$is_alive()) r$kill()
srv$stop()
```
Output:
```
<curl handle> (http://127.0.0.1:29418/sse?id=BG&n=30&delay=0.1)
started; tokens so far: 0 
 user command 1 at the prompt; tokens so far: 7 
 user command 2; tokens so far: 20 done: FALSE 
 user command 3; tokens so far: 30 done: TRUE 
```

### 5.15 External CLI agents in parallel (`p7_cli_agents.R`)

```r
# p7_cli_agents.R -- PROTOTYPE (e): external CLI agents (claude -p / codex exec) as parallel sub-agents.
# Real CLIs are NOT called (no model usage). Fake CLIs written in R print the documented JSONL shapes:
#   claude -p --output-format stream-json --verbose : {"type":"system","subtype":"init",...} ... {"type":"result",...}
#   codex exec --json                               : thread.started, turn.started, item.completed, turn.completed
# The runner: prompt via a stdin file (no quoting / command-line length limits on Windows), JSONL parsed
# incrementally from processx pipes, one processx::poll() over all children, max_active slots, per-agent
# timeout, failure isolation, usage aggregation.
now <- function() as.numeric(Sys.time())
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/15"
fake <- file.path(W, "fake_cli.R")
writeLines(r"---(
a <- commandArgs(TRUE); kind <- a[1]; secs <- as.numeric(a[2]); fail <- identical(a[3], "fail")
prompt <- paste(readLines(file("stdin")), collapse = "\n")
out <- function(x) { cat(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"), "\n", sep = ""); flush(stdout()) }
if (kind == "claude") {
  out(list(type = "system", subtype = "init", session_id = "s-1", model = "claude-sonnet-x", tools = list("Read", "Grep")))
  for (i in 1:3) { Sys.sleep(secs / 4); out(list(type = "assistant", parent_tool_use_id = NULL,
    message = list(role = "assistant", content = list(list(type = "text", text = sprintf("step %d", i)))))) }
  Sys.sleep(secs / 4)
  if (fail) { out(list(type = "result", subtype = "error_during_execution", is_error = TRUE, result = "auth failed",
                       session_id = "s-1", total_cost_usd = 0, num_turns = 1, usage = list(input_tokens = 10, output_tokens = 0))); quit(status = 1) }
  out(list(type = "result", subtype = "success", is_error = FALSE, result = paste("claude answer to:", prompt),
           session_id = "s-1", total_cost_usd = 0.0123, num_turns = 3, duration_ms = secs * 1000,
           usage = list(input_tokens = 1200, output_tokens = 300, cache_read_input_tokens = 800)))
} else {
  out(list(type = "thread.started", thread_id = "t-1")); out(list(type = "turn.started"))
  Sys.sleep(secs / 2); out(list(type = "item.completed", item = list(id = "item_0", type = "reasoning", text = "thinking")))
  Sys.sleep(secs / 2); out(list(type = "item.completed", item = list(id = "item_1", type = "agent_message", text = paste("codex answer to:", prompt))))
  out(list(type = "turn.completed", usage = list(input_tokens = 900, cached_input_tokens = 600, output_tokens = 150)))
}
)---", fake)

# ---- runner ------------------------------------------------------------------------------------
cli_spec <- function(kind, prompt, secs, fail = FALSE, timeout = Inf, name = kind) {
  list(name = name, kind = kind, prompt = prompt, timeout = timeout,
       # in gptr: cmd = Sys.which("claude"), args = c("-p", "--output-format", "stream-json", "--verbose", ...)
       cmd = file.path(R.home("bin"), "Rscript"), args = c("--vanilla", fake, kind, secs, if (fail) "fail"))
}
parse_event <- function(st, ev) {
  if (st$kind == "claude") {
    if (identical(ev$type, "assistant")) st$progress <- st$progress + 1L
    if (identical(ev$type, "result")) { st$text <- ev$result; st$is_error <- isTRUE(ev$is_error)
      st$usage <- st$usage + c(ev$usage$input_tokens %||% 0, ev$usage$output_tokens %||% 0); st$cost <- ev$total_cost_usd %||% NA }
  } else {
    if (identical(ev$type, "item.completed") && identical(ev$item$type, "agent_message")) st$text <- ev$item$text
    if (identical(ev$type, "item.completed")) st$progress <- st$progress + 1L
    if (identical(ev$type, "turn.completed")) st$usage <- st$usage + c(ev$usage$input_tokens, ev$usage$output_tokens)
    if (ev$type %in% c("turn.failed", "error")) st$is_error <- TRUE
  }
  st
}
`%||%` <- function(a, b) if (is.null(a)) b else a
run_cli_agents <- function(specs, max_active = 2L, on_event = function(name, ev) NULL) {
  n <- length(specs); st <- vector("list", n); procs <- list(); t0 <- now()
  on.exit(for (p in procs) if (!is.null(p) && p$is_alive()) p$kill_tree(), add = TRUE)   # Ctrl-C / error cleanup
  next_i <- 1L
  start <- function(i) {
    s <- specs[[i]]; f <- tempfile(fileext = ".txt"); writeLines(s$prompt, f, useBytes = TRUE)
    p <- processx::process$new(s$cmd, s$args, stdin = f, stdout = "|", stderr = "|",
                               supervise = TRUE, cleanup_tree = TRUE)
    st[[i]] <<- list(name = s$name, kind = s$kind, text = NA_character_, is_error = FALSE, usage = c(input = 0, output = 0),
                     cost = NA, progress = 0L, t_start = now() - t0, deadline = now() + s$timeout, stderr = "", partial = "")
    procs[[i]] <<- p
  }
  repeat {
    running <- which(vapply(seq_len(n), function(i) length(procs) >= i && !is.null(procs[[i]]) && is.null(st[[i]]$status), NA))
    while (length(running) < max_active && next_i <= n) { start(next_i); running <- c(running, next_i); next_i <- next_i + 1L }
    if (!length(running)) break
    processx::poll(procs[running], 200L)
    for (i in running) {
      p <- procs[[i]]
      chunk <- p$read_output()                                   # non-blocking; may end mid-line
      if (nzchar(chunk)) {
        buf <- paste0(st[[i]]$partial, chunk); lines <- strsplit(buf, "\n", fixed = TRUE)[[1]]
        complete <- endsWith(buf, "\n"); st[[i]]$partial <- if (complete) "" else lines[length(lines)]
        if (!complete) lines <- lines[-length(lines)]
        for (ln in lines[nzchar(trimws(lines))]) {
          ev <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) NULL)   # ignore non-JSON noise
          if (!is.null(ev)) { st[[i]] <- parse_event(st[[i]], ev); on_event(st[[i]]$name, ev) }
        }
      }
      st[[i]]$stderr <- paste0(st[[i]]$stderr, p$read_error())
      if (now() > st[[i]]$deadline && p$is_alive()) { p$kill_tree(); st[[i]]$status <- "timeout"; st[[i]]$is_error <- TRUE }
      else if (!p$is_alive() && !p$is_incomplete_output()) {
        st[[i]]$exit <- p$get_exit_status()
        st[[i]]$status <- if (st[[i]]$is_error || st[[i]]$exit != 0) "error" else "ok"
      }
      if (!is.null(st[[i]]$status)) st[[i]]$t_end <- now() - t0
    }
  }
  st
}

specs <- list(
  cli_spec("claude", "Review analysis.R for statistical errors", 2.0, name = "claude-review"),
  cli_spec("codex",  "Review analysis.R for code errors",       1.6, name = "codex-review"),
  cli_spec("claude", "Check the biology",                       1.2, fail = TRUE, name = "claude-bio"),
  cli_spec("codex",  "Summarise cohort 4",                      3.0, timeout = 1.5, name = "codex-slow"),
  cli_spec("claude", "Write tests",                             1.0, name = "claude-tests"))
t0 <- now()
res <- run_cli_agents(specs, max_active = 3L)
wall <- now() - t0
for (r in res) cat(sprintf("%-14s %-7s started %.2fs ended %.2fs exit=%s events=%d usage in/out=%g/%g cost=%s | %s\n",
  r$name, r$status, r$t_start, r$t_end, format(r$exit %||% NA), r$progress, r$usage[1], r$usage[2], format(r$cost), substr(r$text %||% "", 1, 55)))
tot <- Reduce(`+`, lapply(res, `[[`, "usage"))
cat(sprintf("WALL %.2fs with max_active = 3 (sum of nominal durations %.1fs) | total usage in/out = %g/%g | ok %d of %d\n",
  wall, 2.0 + 1.6 + 1.2 + 3.0 + 1.0, tot[1], tot[2], sum(vapply(res, function(r) r$status == "ok", NA)), length(res)))
```
Output:
```
claude-review  ok      started 0.03s ended 2.23s exit=0 events=3 usage in/out=1200/300 cost=0.0123 | claude answer to: Review analysis.R for statistical err
codex-review   ok      started 0.03s ended 1.83s exit=0 events=2 usage in/out=900/150 cost=NA | codex answer to: Review analysis.R for code errors
claude-bio     error   started 0.04s ended 1.44s exit=1 events=3 usage in/out=10/0 cost=0 | auth failed
codex-slow     timeout started 1.45s ended 3.02s exit=NA events=0 usage in/out=0/0 cost=NA | NA
claude-tests   ok      started 1.84s ended 3.05s exit=0 events=3 usage in/out=1200/300 cost=0.0123 | claude answer to: Write tests
WALL 3.08s with max_active = 3 (sum of nominal durations 8.8s) | total usage in/out = 3310/750 | ok 3 of 5
```

### 5.16 Agent definition files (`p8_agent_files.R`)

```r
# p8_agent_files.R -- agent definition files: Markdown + YAML frontmatter, compatible with
# Claude Code (.claude/agents/**/*.md) and Pi's subagent example (.pi/agents/*.md). Parse, normalise, discover.
PI <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi"
`%||%` <- function(a, b) if (is.null(a)) b else a

split_frontmatter <- function(lines) {
  if (!length(lines) || !grepl("^---\\s*$", lines[1])) return(list(meta = list(), body = paste(lines, collapse = "\n")))
  end <- which(grepl("^---\\s*$", lines))[2]
  if (is.na(end)) return(NULL)                                   # unterminated frontmatter
  meta <- tryCatch(yaml::yaml.load(paste(lines[2:(end - 1)], collapse = "\n")) %||% list(), error = function(e) NULL)
  if (is.null(meta) || !is.list(meta)) return(NULL)
  list(meta = meta, body = trimws(paste(lines[-seq_len(end)], collapse = "\n")))
}
as_chr_list <- function(x) {                                     # "a, b" or [a, b] -> c("a","b"); anything else -> NULL
  v <- if (is.character(x) && length(x) == 1) strsplit(x, ",", fixed = TRUE)[[1]] else if (is.list(x) || is.character(x)) unlist(x) else NULL
  v <- trimws(as.character(v[vapply(v, is.character, NA)])); v <- v[nzchar(v)]
  if (length(v)) v else NULL
}
# Claude Code / Pi tool names -> gptr tool names (S-4: no bash tool; the R tool is the execution tool)
tool_map <- c(read = "read", write = "write", edit = "edit", multiedit = "edit", grep = "grep", glob = "find", find = "find",
              ls = "ls", bash = "r", powershell = "r", r = "r", agent = "agent", task = "agent", askuserquestion = "ask",
              webfetch = "web_fetch", websearch = "web_search")
map_tools <- function(tools) {
  if (is.null(tools)) return(NULL)
  base <- tolower(sub("\\(.*$", "", tools))                       # "Bash(git diff *)" -> "bash"
  out <- ifelse(startsWith(base, "mcp__"), tools, tool_map[base])
  unknown <- tools[is.na(out)]
  structure(unique(out[!is.na(out)]), unknown = unknown)
}
read_agent_file <- function(path, source = "project") {
  parts <- split_frontmatter(readLines(path, warn = FALSE, encoding = "UTF-8"))
  if (is.null(parts)) return(structure(list(file = path, reason = "unparseable frontmatter"), class = "gptr_agent_skip"))
  m <- parts$meta   # always m[["field"]]: m$mode would partially match `model`
  if (!is.character(m[["name"]]) || !is.character(m[["description"]]))
    return(structure(list(file = path, reason = "name and description must be strings"), class = "gptr_agent_skip"))
  if (grepl(":", m[["name"]], fixed = TRUE) || startsWith(m[["name"]], "-"))
    return(structure(list(file = path, reason = "invalid name"), class = "gptr_agent_skip"))
  tools <- map_tools(as_chr_list(m[["tools"]]))
  structure(list(
    name = m[["name"]], description = m[["description"]],
    system_prompt = parts$body,
    tools = if (length(tools)) as.character(tools) else NULL,            # NULL = harness default tool set
    disallowed_tools = as.character(map_tools(as_chr_list(m[["disallowedTools"]]))) %||% character(),
    model = if (is.character(m[["model"]]) && m[["model"]] != "inherit") m[["model"]] else NULL,   # NULL = inherit the caller's model
    effort = m[["effort"]] %||% m[["thinking"]] %||% NULL,
    max_turns = if (is.numeric(m[["maxTurns"]])) as.integer(m[["maxTurns"]]) else NULL,
    permission_mode = m[["permissionMode"]] %||% NULL,
    skills = as_chr_list(m[["skills"]]), mcp_servers = m[["mcpServers"]] %||% NULL,
    mode = m[["mode"]] %||% NULL,                                             # gptr extension: inline | worker | cli
    unknown_tools = attr(tools, "unknown"), extra = m[setdiff(names(m), c("name", "description", "tools", "disallowedTools",
      "model", "effort", "thinking", "maxTurns", "permissionMode", "skills", "mcpServers", "mode"))],
    source = source, file = path), class = "gptr_agent")
}
# discovery: later entries override earlier ones by name (low -> high precedence)
agent_dirs <- function(cwd = getwd(), user_home = path.expand("~")) {
  up <- function(sub) { d <- normalizePath(cwd, mustWork = FALSE)
    repeat { cand <- file.path(d, sub); if (dir.exists(cand)) return(cand); p <- dirname(d); if (p == d) return(NULL); d <- p } }
  c(user_pi = file.path(user_home, ".pi", "agent", "agents"), user_claude = file.path(user_home, ".claude", "agents"),
    user_gptr = file.path(tools::R_user_dir("gptr", "config"), "agents"),
    project_pi = up(".pi/agents") %||% NA, project_claude = up(".claude/agents") %||% NA, project_gptr = up(".gptr/agents") %||% NA)
}
discover_agents <- function(dirs) {
  found <- list(); skipped <- list()
  for (nm in names(dirs)) { d <- dirs[[nm]]; if (is.na(d) || !dir.exists(d)) next
    recursive <- grepl("claude|gptr", nm)                                  # Claude Code scans recursively; Pi does not
    for (f in sort(list.files(d, pattern = "\\.md$", full.names = TRUE, recursive = recursive))) {
      a <- read_agent_file(f, source = nm)
      if (inherits(a, "gptr_agent_skip")) skipped[[length(skipped) + 1L]] <- a else found[[a$name]] <- a
    }
  }
  structure(found, skipped = skipped)
}

# ---- test on Pi's real agent files and synthetic Claude Code files ---------------------------------
tmp <- file.path(tempdir(), "proj"); dir.create(file.path(tmp, ".claude", "agents", "review"), recursive = TRUE)
dir.create(file.path(tmp, ".pi", "agents"), recursive = TRUE); dir.create(file.path(tmp, ".gptr", "agents"), recursive = TRUE)
invisible(file.copy(list.files(file.path(PI, "packages/coding-agent/examples/extensions/subagent/agents"), full.names = TRUE), file.path(tmp, ".pi", "agents")))
writeLines(c("---", "name: stats-reviewer", "description: Reviews statistical methodology. Use after model fitting.",
  "tools: [Read, Grep, Glob, Bash(Rscript *), mcp__github__search_code, NotebookEdit]", "disallowedTools: Write",
  "model: opus", "maxTurns: 12", "permissionMode: plan", "effort: high", "skills: statistics, single-cell",
  "color: blue", "memory: project", "---", "", "You are a careful statistician. Check assumptions first."),
  file.path(tmp, ".claude", "agents", "review", "stats.md"))
writeLines(c("---", "name: scout", "description: gptr override of Pi's scout", "mode: inline", "---", "Look at the objects in memory first."),
  file.path(tmp, ".gptr", "agents", "scout.md"))
writeLines(c("---", "name: broken", "description: [unclosed", "---", "x"), file.path(tmp, ".claude", "agents", "broken.md"))
writeLines(c("---", "description: no name here", "---", "x"), file.path(tmp, ".claude", "agents", "noname.md"))
dirs <- agent_dirs(cwd = file.path(tmp, ".claude"), user_home = file.path(tempdir(), "nohome"))
ag <- discover_agents(dirs)
for (a in ag) cat(sprintf("%-15s source=%-14s model=%-16s tools=%-32s max_turns=%-3s mode=%-6s unknown_tools=%s extra=%s\n",
  a$name, a$source, format(a$model %||% "(inherit)"), paste(a$tools %||% "(default)", collapse = ","), format(a$max_turns %||% "-"),
  format(a$mode %||% "-"), paste(a$unknown_tools, collapse = ","), paste(names(a$extra), collapse = ",")))
for (s in attr(ag, "skipped")) cat(sprintf("skipped %s: %s\n", basename(s$file), s$reason))
cat("stats-reviewer disallowed:", ag[["stats-reviewer"]]$disallowed_tools, "| skills:", ag[["stats-reviewer"]]$skills, "\n")
cat("system prompt of scout (gptr override wins):", ag$scout$system_prompt, "\n")
```
Output:
```
planner         source=project_pi     model=claude-sonnet-4-5 tools=read,grep,find,ls                max_turns=-   mode=-      unknown_tools= extra=
reviewer        source=project_pi     model=claude-sonnet-4-5 tools=read,grep,find,ls,r              max_turns=-   mode=-      unknown_tools= extra=
scout           source=project_gptr   model=(inherit)        tools=(default)                        max_turns=-   mode=inline unknown_tools= extra=
worker          source=project_pi     model=claude-sonnet-4-5 tools=(default)                        max_turns=-   mode=-      unknown_tools= extra=
stats-reviewer  source=project_claude model=opus             tools=read,grep,find,r,mcp__github__search_code max_turns=12  mode=-      unknown_tools=NotebookEdit extra=color,memory
skipped broken.md: unparseable frontmatter
skipped noname.md: name and description must be strings
stats-reviewer disallowed: write | skills: statistics single-cell 
system prompt of scout (gptr override wins): Look at the objects in memory first.
```
Before switching to `[[`, the same run printed `mode=claude-sonnet-4-5` for planner/reviewer/worker and `mode=opus` for stats-reviewer (partial matching of `$mode` to `model`).

### 5.17 Not run

- Nothing on Windows or Linux.
- No real `claude -p` / `codex exec` run and no real provider stream (no paid calls).
- HTTP/2 multiplexing behaviour with `pipewait = 0` against a real HTTPS provider.
- mirai 2.7.x, mori on Windows, mori on R >= 4.5.
- Background mode in RStudio, Positron, Jupyter, knitr.
- `setTimeLimit()` tool timeouts; orphan sweep after a hard crash; the gptr MCP bridge for CLI agents.

---

## 6. CRAN and cross-platform considerations

**CRAN**
- Never exceed 2 concurrent child processes in examples, tests and vignettes. Compute worker limits through a helper that returns ≤ 2 when `_R_CHECK_LIMIT_CORES_` is set (parallelly does this; §5.8), and default tests to inline mode with the built-in fake provider (D-24), which needs no processes or sockets.
- Examples: inline + fake provider only; worker/cli examples in `\donttest{}` or `if (interactive())`. Tests that start the base-R mock server or any worker: `skip_on_cran()`; always stop servers/processes with `withr::defer()`/`on.exit()`; close every httr2 streaming response (`_R_CHECK_CONNECTIONS_LEFT_OPEN_` treats open connections from examples as fatal).
- Do not modify the user's `future::plan()`, `options(mc.cores)`, RNG kind or seed (§5.12 restores both), or global env bindings (the guard unlocks everything it locked in `on.exit`).
- No writes outside `tempdir()` without consent: agent-file discovery only reads `~/.claude/agents`, `~/.pi/agent/agents`; the orphan-marker file goes under `tools::R_user_dir("gptr", "cache")` only after initialisation consent (D-10).
- Don't leave `later` callbacks scheduled after an example; background jobs must be cancelled at the end of examples.
- mori has no R 4.4 binary (the R 4.4 repository is frozen), but CRAN currently builds 0.2.2 binaries for Windows (r-devel/r-release/r-oldrel) and macOS (r-release/r-oldrel, arm64 and x86_64); if it is ever moved to Imports, re-check (it is Suggests in this design).

**Windows specifics**
- No fork: `mcparallel()`/`mclapply(mc.cores > 1)` are unavailable; `mode = "fork"` must error with a clear message; worker mode uses callr (Rterm children).
- `process$interrupt()` sends CTRL+BREAK (processx docs); `signal()` interprets only SIGINT, SIGTERM, SIGKILL and all three kill the process; `tools::pskill(SIGINT)` is not a graceful interrupt there. For CLI agents on Windows there is no graceful "end the turn" signal; kill after marking the run aborted.
- `kill_tree()` works on Windows via the ps environment-variable marker; `supervise = TRUE` works (processx docs); both UNTESTED here.
- `processx::poll()` uses IOCP and supports curl fds on Windows (processx NEWS); `later::later_fd()` only monitors sockets (WSAPoll), so background mode can watch HTTP sockets but not child pipes: poll processes from a periodic `later::later()` timer instead.
- Command lines are limited to 32,767 characters and npm-installed CLIs are `.cmd` shims: never pass prompts as arguments; write them to a temp file and use `stdin = <file>` (as in §5.15). Running a `.cmd` shim needs `cmd.exe /d /s /c` with careful quoting (argument-injection class of bugs, e.g. CVE-2024-24576 "BatBadBut"); prefer resolving the shim to the real executable (`claude.exe` from the native installer; for codex the underlying `node` + script). UNCERTAIN, needs a Windows test.
- Encoding: JSONL over pipes must be UTF-8 (`enc2utf8()`, `useBytes = TRUE`, `readLines(encoding = "UTF-8")`); R >= 4.2 on Windows uses UTF-8 natively, R 4.1 does not. If D-23 keeps R >= 4.1, test JSONL with non-ASCII text on R 4.1 Windows.
- Paths: use `file.path(R.home("bin"), "Rscript")` (callr handles this), `Sys.which()` for CLIs, `normalizePath(winslash = "/")` in prompts.
- mori uses Win32 file mappings on Windows (DESCRIPTION); mirai uses named pipes/IPC via nanonext; both UNTESTED here.
- Interrupt sources: Rgui uses Esc, Rterm Ctrl-C, RStudio the stop button; all set R's interrupt flag, which curl's loops, `Sys.sleep` and R code check (LIKELY; only macOS measured).

**IDEs and front ends**
- RStudio: no fork (`supportsMulticore()` FALSE); `\r` progress works (cli); later callbacks run when idle (LIKELY).
- Positron, Jupyter/IRkernel, knitr/Quarto: progress falls back to event lines (non-dynamic); background mode UNCERTAIN; inline and worker modes do not depend on the front end.

---

## 7. Risks, pitfalls, open questions

**Pitfalls (all observed in this work)**
1. `CURLOPT_PIPEWAIT` default serializes long streams to HTTP/1.1 hosts through any shared pool (curl, `req_perform_parallel`, `req_perform_promise`, ellmer `parallel_chat`). Always set `pipewait = 0L`.
2. mirai daemons do not inherit `.libPaths()`; a failed start makes `daemons()` wait forever (2.6.1). Propagate `R_LIBS`, and wrap start-up in a timeout.
3. callr defaults `user_profile = "project"`: workers source the project's `.Rprofile`. Pass `user_profile = FALSE`.
4. `as.numeric(seq_len(n))` is a compact ALTREP sequence: memory benchmarks on it are meaningless. Use `runif()`.
5. `lockBinding()` fails with "bad binding access" on a top-level `for` index; re-assign first.
6. `$` partial matching on parsed YAML (`meta$mode` → `model`). Use `[[`.
7. mori shared vectors silently become private copies under most operations and under R's copy-on-modify; `is_shared()` still says TRUE; element-wise arithmetic on them is very slow; `.Internal(inspect())` materializes them. Verify sharing by serialized size.
8. processx's supervisor kills only direct children after a hard crash; grandchildren (CLI tool subprocesses, MCP servers) survive.
9. `tryCatch(interrupt = )` runs after `on.exit` handlers; do cleanup in `on.exit`, record partial results in the handler, then re-signal.
10. OS RSS on macOS is distorted by memory compression under load; use R-level accounting.

**Risks**
- A long R tool call stalls every inline agent's tool queue (streams keep buffering). Mitigations: per-tool time limit, route heavy compute to worker mode, show the running tool in the status line.
- Inline sub-agents can mutate reference objects (environments, R6, Seurat internals, data.table) in the user's workspace; the guard cannot prevent it. Mitigation: advisory classifier + permission mode + documentation; worker mode for untrusted plans.
- Parallel agents multiply API cost and hit rate limits quickly; per-provider concurrency caps and 429/529 back-off are required, and usage must roll up to the parent (Pi's example forgets to).
- Parallel file edits by several agents on one working tree: needs per-file locks or `isolation: worktree`-style copies (open question already in the digest).
- Background mode executes agent tool calls between user commands; users may be surprised by objects changing. Keep background agents inline-read-only unless `export` is explicit.
- Measurement noise: all numbers were taken with load 20-150 from other jobs; absolute values will be lower on an idle machine, the relative conclusions held across repeated runs.

**Open questions for the maintainer / other tracks**
1. Default mode for `gptr_parallel()`/`gptr_map()`: inline (zero-copy, concurrent I/O, serialized tools) or worker (CPU parallel, copies data)? This report recommends inline by default, worker on request.
2. Ship background jobs (`background = TRUE`, needs `later`) in v1, or later?
3. Should mori be a Suggests dependency with automatic use for large atomic/data-frame objects in worker mode, given the materialization behaviour on R 4.4.3? Re-test on R 4.5/4.6 first.
4. Is `mode = "fork"` worth offering at all (Unix terminals only, discouraged by R docs in multi-threaded processes)?
5. Default depth for nested sub-agents (1 here; Claude Code uses 3).
6. Should the reactor also drive single-agent `gptr()` calls (one code path, recommended) or should single calls use `httr2::req_perform_connection()` (report 00-digest line 174 suggested two transports)? Measurements show one curl-multi path is enough.
7. Can the gptr MCP server (D-14) serve tool calls from CLI sub-agents while the parent reactor is running (bridge process + local socket), giving CLI agents access to live objects?
8. Windows verification of every VERIFIED-on-macOS item in §6.

---

## 8. Sources

Local source and files (read first-hand):
- Pi clone at `scratchpad/pi`, commit `1b34779` (2026-09-29 22:47:17 +0200): `packages/coding-agent/examples/extensions/subagent/index.ts` lines 33-36, 219-237, 300, 413-415, 424, 610; `.../subagent/agents.ts` lines 11-19, 34-39, 53; `.../subagent/agents/scout.md`; `packages/agent/src/types.ts` lines 39-47, 305-317, 486-497; `packages/agent/src/agent.ts` line 253; `packages/agent/src/agent-loop.ts` lines 505-523.
- `/Users/wanjun/Desktop/gptr/dev/spec/00-vision-brief.md`, `01-decision-register.md` (D-04, D-12, D-13, D-20, D-28), `02-north-star-examples.md` §6; `/Users/wanjun/Desktop/gptr/dev/research/06-pi-subagents-mcp-codemode.md` §2.1, §3.1-3.2, §4.2; `00-digest.md`.
- Installed package documentation and NEWS (R 4.4.3 framework library): `curl/NEWS` (6.1.0, 6.2.3, 7.0.0), `processx/NEWS.md`, `callr/NEWS.md`, `httpuv/NEWS.md`, help pages `processx::poll`, `processx::curl_fds`, `processx::process`, `later::later_fd`, `cli::is_dynamic_tty`, `httr2::req_perform_connection`, `httr2::resp_stream_raw`, `base::socketSelect`, `parallel::mcfork`, `mori::share`; printed functions `httr2:::ensure_pool_poller`, `httr2:::pool_wait`, `httr2::req_perform_promise`, `ellmer:::chat_perform_async_stream`, `ellmer:::chat_perform_stream`, `ellmer:::parallel_turns`, `ellmer:::chat_perform`.
- CLI help: `claude --help` (2.1.261), `codex exec --help` (codex-cli 0.157.0).
- Prototype scripts and outputs: `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/15/` (`mock_sse_base.R`, `sse.R`, `p0`-`p16g`, `*_output.txt`; previous researcher's `mock_llm.R`, `a0_smoke.R`, `a1_curl_multi.R`, `a1b_server_check.R`, `install_private*.R`).

Web:
- Claude Code sub-agents: https://code.claude.com/docs/en/sub-agents
- Claude Code headless / `claude -p`: https://code.claude.com/docs/en/headless
- Codex non-interactive mode: https://learn.chatgpt.com/docs/non-interactive-mode (redirect target of https://developers.openai.com/codex/noninteractive)
- Codex `exec --json` event cheat sheet (third party): https://takopi.dev/reference/runners/codex/exec-json-cheatsheet/
- CRAN Repository Policy: https://cran.r-project.org/web/packages/policies.html
- R Internals, Tools (`_R_CHECK_*` variables): https://rstudio.github.io/r-manuals/r-ints/Tools.html
- mirai `daemons()` reference: https://mirai.r-lib.org/reference/daemons.html
- mirai NEWS: https://mirai.r-lib.org/news/index.html
- mirai CRAN page: https://cran.r-project.org/web/packages/mirai/index.html
- mori CRAN page: https://cran.r-project.org/web/packages/mori/index.html; README: https://github.com/shikokuchuo/mori
- httr2 NEWS: https://httr2.r-lib.org/news/index.html
- curl NEWS: https://github.com/jeroen/curl/blob/master/NEWS
- parallelly `availableCores()`: https://cran.r-project.org/web/packages/parallelly/refman/parallelly.html

---

## Verification log

Independent adversarial check, 2026-09-29, same machine (load averages 20-180 during the checks). Method: every R listing in §5 (23 blocks) was extracted verbatim from this report into `scratchpad/work/verify-15/` (only the `work/15` path constant rewritten to `work/verify-15`) and re-run with `R_LIBS=<scratchpad>/rlib Rscript --vanilla`; 21 listings are byte-identical to the original scratch scripts, `p0` and `p16c` differ only by header comment lines omitted from the report, and all 23 ran to completion (exit 0). Outputs are in `verify-15/out_*.txt` and `verify-15/outC_*.txt`. Extra verifier scripts: `p13b_idle_check.R`, `nb10ms.R`, `sigs.R`, `rd.R`. Web pages were fetched on the same date; CRAN source tarballs of ellmer 0.5.0, mirai 2.7.3 and httr2 1.3.0 were downloaded to `verify-15/src/` (not installed).

| # | Claim (section) | Verdict | Source / evidence |
|---|---|---|---|
| 1 | curl 6.1.0 turned `CURLOPT_PIPEWAIT` on by default and added `max_streams` (default 10); unchanged through 8.1.0 (§2.2) | confirmed | local `curl/NEWS`; GitHub `jeroen/curl` NEWS (7.x/8.x entries have no pipewait change) |
| 2 | Default pool stalls 6 streams (3.51 s) and `pipewait = 0` fixes it (2.30 s); 20 streams 2.33-2.34 s (§1, §5.2) | confirmed | re-run `p1`: 3.52 s vs 2.31 s; 20 streams 2.35 s; `[PASS]` |
| 3 | `a2_pool_diag.R`: default pool 2.46 s, streams 2-4 start at 1.23 s (§2.2) | corrected | two re-runs: 4.94 s / 5.11 s, first bytes 0/1.24/2.5/3.7-3.9 s (fully serialized); `host_con = 100` 4.14-5.03 s; fixes 1.25-1.36 s. Text now says the stall can serialize all N streams |
| 4 | httr2 `req_perform_promise()`/`req_perform_parallel()` affected, `req_perform_connection()` not (§2.2, §5.3) | confirmed | re-run `p2` twice at load ~22: V3 3.39-3.41 vs 2.28-2.29 s, V4 3.41 vs 2.28 s, V1 2.39-2.44 vs 2.30 s |
| 5 | coro variant uses "4-8x more CPU" (§1, §2.3) | corrected | table itself shows 0.81 s vs 0.44 s (curl multi) vs 0.11 s (httr2 V1); re-runs 0.61-0.92 vs 0.26 vs 0.10-0.21 s. Reworded to "2-3x curl multi, 4-8x round-robin httr2"; one high-load run collapsed to 5.33 s |
| 6 | ellmer `parallel_chat()` -> `parallel_turns()` -> `req_perform_parallel()` without `pipewait`; signature `max_active = 10, rpm = 500, on_error = c("return","continue","stop")` (§2.2, §2.14) | confirmed | printed `ellmer:::parallel_turns` (0.4.0); ellmer 0.5.0 CRAN source `R/parallel-chat.R:338`; `args(ellmer::parallel_chat)` |
| 7 | curl 6.2.3 non-blocking connections wait 10 ms (§2.2) | confirmed | local `curl/NEWS` line 25; measured 11.1 ms per idle `resp_stream_sse()` call |
| 8 | Every signature in §3.1 (curl, processx, later, callr, mirai 2.6.1, mori, parallel, parallelly, httr2) and `r_session` method list | confirmed | `args()` on installed versions (`verify-15/sigs.R`) |
| 9 | callr `r_bg()`/`r_session_options()` default `user_profile = "project"` (§2.6) | confirmed | `args(callr::r_bg)`, `callr::r_session_options()` |
| 10 | mirai 2.7.x `daemons()` adds `memory = NULL`; 2.7.0 dispatcher is a thread; 2.7.0 fixes >~2 GB transfers on macOS/Windows (§2.6, §3.1) | confirmed | mirai 2.7.3 `R/daemons.R:226-239`, `NEWS.md`; https://mirai.r-lib.org/reference/daemons.html |
| 11 | mirai quotes on `daemons(0)` / host-session exit (§2.6) | corrected | were paraphrases in quote marks; replaced with the verbatim reference-page text |
| 12 | "2.6.0: `stop_mirai()` returns logical" (§2.6) | corrected | NEWS: logical return added in 2.0.0; always FALSE without dispatcher (`R/mirai.R` @return). `race_mirai()` index return in 2.6.0 confirmed |
| 13 | Local mirai daemons do not get the parent's `.libPaths()`, "LIKELY for 2.7.x" (§2.6) | confirmed (upgraded) | 2.7.3 source: `launch_daemon()` = `system2(Rscript, c("-e", "mirai::daemon(...)"))`; `.libPaths()` only propagated in the Workbench launcher |
| 14 | CRAN versions in the header and §5.0 (mirai 2.7.3, nanonext 1.10.3, crew 1.3.3, parallelly 1.48.0, callr 3.8.0, processx 3.9.0, httr2 1.3.0, curl 8.0.0, future 1.76.0, webfakes 1.5.0, mori 0.2.2, later/promises/coro unchanged) and crew's Imports | confirmed | `available.packages()` against cloud.r-project.org (source); ellmer 0.5.0 added |
| 15 | callr "only adds R6/processx" (§1, §4.12) | corrected | callr 3.8.0 Imports `otel (>= 0.2.0), processx (>= 3.6.1), R6, utils`; otel has no hard deps |
| 16 | mori 0.2.2 by the mirai author (2026-07), DESCRIPTION text, Depends R >= 4.3, Suggests mirai/testthat, exports (§2.7) | confirmed | installed DESCRIPTION (Charlie Gao, published 2026-07-21), `getNamespaceExports("mori")`, CRAN page |
| 17 | mori binary availability ("check binary availability", "no R 4.4 binary") (§4.12, §6) | corrected | CRAN page lists 0.2.2 binaries for Windows r-devel/r-release/r-oldrel and macOS r-release/r-oldrel (arm64, x86_64) |
| 18 | mori `?share` quotes, coverage, slot sharing 572 bytes, materialization list, `v * 2` slow, worker heap deltas (§2.7, §5.7) | confirmed | re-run `p16b`, `p16g` (`v * 2` 3.23 s), `p16c` (152.5 MB deltas, `is_shared()` TRUE throughout), `p4` coverage; `Rd2txt` of `share.Rd` |
| 19 | `?mcfork` "strongly discouraged" quotes (§2.8) | confirmed | `tools::Rd_db("parallel")[["unix/mcfork.Rd"]]` |
| 20 | `supportsMulticore()` FALSE with `RSTUDIO=1`; `availableCores()` 2 under `_R_CHECK_LIMIT_CORES_`, min over sources with `mc.cores` (§2.8, §2.15) | confirmed | executed; also `availableCores(omit = 1)` = 1 under `_R_CHECK_LIMIT_CORES_` (added to §3.7) |
| 21 | Pi subagent constants and line numbers (33/34/36, 219-237, 300, 413/415, 424, 610) and result wording in §3.5 (§2.14) | confirmed, with caveat | `scratchpad/pi` @ 1b34779 `index.ts`; caveat added: `if (!proc.killed)` skips SIGKILL after a delivered SIGTERM (Node docs: `killed` = signal successfully received, not exited) |
| 22 | Pi `ToolExecutionMode` (types.ts:47), default "parallel" (agent.ts:253), per-tool `executionMode` (types.ts:496), sequential-forces-batch (agent-loop.ts:516-521) (§2.14) | confirmed | Pi source |
| 23 | Pi `agents.ts:11-19`, `34-39`, `parseToolList` at 53, `scout.md` frontmatter (§2.12) | confirmed | Pi source |
| 24 | Claude Code sub-agent frontmatter fields/values, depth 3 (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`), concurrency 20 (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, "Concurrent subagent limit reached"), precedence, recursion, `Agent` (formerly `Task`), `--agents` JSON (§2.12, §3.3) | confirmed | https://code.claude.com/docs/en/sub-agents (note added: `manual` is an alias for `default`) |
| 25 | "Claude Code caps combined descriptions at 15,000 tokens" (§4.9) | corrected | same page: exceeding 15,000 tokens only triggers a startup warning; all agents still load |
| 26 | Claude headless: exit codes, failures printed as result, `--bare` skips discovery and needs `ANTHROPIC_API_KEY`, SIGTERM -> 143 / SIGINT ends turn, 10 MB stdin cap, `system/api_retry`, `parent_tool_use_id`, `total_cost_usd` (§2.9) | confirmed, caveats added | https://code.claude.com/docs/en/headless: `--bare` "will become the default for `-p` in a future release"; non-bare `-p` runs project hooks/MCP in untrusted folders; `system/init` may be preceded by startup events |
| 27 | `claude --help` flags and `--permission-mode` choices; `codex exec --help` flags (§2.9, §3.4) | confirmed | local `claude --help` (2.1.261), `codex exec --help` (codex-cli 0.157.0) |
| 28 | Codex docs: event and item types, read-only default sandbox, `CODEX_API_KEY` quote, example lines "from third-party cheat sheets, LIKELY" (§2.9, §3.4) | corrected | https://learn.chatgpt.com/docs/non-interactive-mode (308 from developers.openai.com/codex/noninteractive): types confirmed; quote replaced; official sample lines exist and include `reasoning_output_tokens` (added to §3.4) |
| 29 | CRAN Repository Policy quotes (§2.15) | confirmed | https://cran.r-project.org/web/packages/policies.html |
| 30 | `_R_CHECK_LIMIT_CORES_`, `_R_CHECK_CONNECTIONS_LEFT_OPEN_`, `_R_CHECK_THINGS_IN_*_DIR_` texts; `--as-cran` enables all four (§2.15) | confirmed | local `R-ints.html` (R 4.4.3); `tools:::.check_packages` sets `_R_CHECK_LIMIT_CORES_=TRUE` under `as_cran` (the rstudio.github.io mirror page returned no text for that variable) |
| 31 | httpuv body is one string/raw vector; `p0` shows one 140-byte chunk (§2.1) | confirmed | `startServer.Rd`; re-run `p0`: single chunk at 1.90 s |
| 32 | webfakes `send_chunk()` + `delay()`, used in httr2's tests (§2.1) | confirmed | `webfakes_response.Rd`; httr2 1.3.0 DESCRIPTION Suggests `webfakes (>= 1.4.0)` |
| 33 | `later_fd` runs only at top level; Windows SOCKETs/`WSAPoll` (§2.5) | confirmed; pipe inference downgraded to LIKELY | `later_fd.Rd` |
| 34 | processx `poll`/`curl_fds` docs, supervisor, `kill_tree()` env-var marker, `interrupt()` = CTRL+BREAK on Windows, `signal()` on Windows, NEWS (IOCP, curl fds on Windows) (§2.4, §2.11) | confirmed | processx Rd pages and `NEWS.md` lines 91, 286 |
| 35 | callr NEWS on `r_session$run*()` interrupts (§2.6) | confirmed | `callr/NEWS.md` lines 187-189 |
| 36 | `cli::is_dynamic_tty()` rules; `p9` piped vs `R_CLI_DYNAMIC=true` (§2.13) | confirmed | `is_dynamic_tty.Rd`; re-run `p9` both modes |
| 37 | `resp_stream_sse()` returns NULL at end or when no event is ready (non-blocking) (§3.1) | confirmed | `resp_stream_raw.Rd` |
| 38 | "httr2 1.2.2 fixed the equivalent quadratic behaviour" (§5.1) | corrected | installed 1.2.2 NEWS has no such entry; https://httr2.r-lib.org/news/: fixed in 1.2.3 (2026-06-23) |
| 39 | Headline inline prototype: concurrent vs sequential, tools never overlap, zero-copy address, isolation (§1, §2.3, §5.4) | confirmed | re-run `p3` at load 160-180: 5.40 s concurrent, 12.40 s at 2, 15.55 s sequential; 0 tokens during the 0.5 s tool (3, not 13-14, within 50 ms after it); address check TRUE |
| 40 | Child-env reads/writes, escape hatches a-h, guard, export policy (§2.10, §5.5) | confirmed | re-run `p5`: identical results; guard 52.6 ms for 2026 bindings |
| 41 | Guard cost ~10-15 µs per binding (§1, §5.13) | confirmed (approx.) | re-run `p15`: lean 22.6 ms min / 33.2 ms median for 2007 bindings (11-17 µs) |
| 42 | Per-agent RNG streams (§5.12) | confirmed | re-run `p14`: identical numbers, user stream untouched |
| 43 | Worker start-up and 496 MB transfer numbers (§2.6, §5.6) | confirmed (qualitatively) | re-run `p4b`: callr 1.70 s, mirai 4.32/2.84 s, fork 0.23 s, `share()` 0.22 s, shared round trips 0.22-0.25 s; `p4`: same ordering |
| 44 | `everywhere()` 29 s "treat as outlier" (§2.6) | corrected | re-run 24.4 s: reproducible, not an outlier |
| 45 | Fork with live curl streams (§2.8, §5.8) | confirmed | re-run `p11`: pong x3, sums ok, 0.19 s, parent 20/20 tokens |
| 46 | One `processx::poll()` reactor for inline + worker + CLI (§2.4, §5.9) | confirmed | re-run `p10`: 2.11 s at load ~22 (3.36 s at load 70-86, first inline token delayed to 1.38 s by child spawning) |
| 47 | Interrupt cleanup and SIGKILL survivors (§2.11, §5.10) | confirmed | re-run `p6`: all 7 pids killed (593 ms at load 180), hard case survivors = unsupervised worker + 2 grandchildren |
| 48 | Interrupt latencies (§2.11) | confirmed | re-run `p12`: 0.001-0.006 s for sleep/curl/httr2/later, 0.203 s poll, 0.265 s callr, 0.317 s mirai, 0.034 s R loop |
| 49 | Background agent at an idle console (§1, §2.5, §5.14) | confirmed (strengthened) | re-run `p13`: 0 -> 6 -> 19 -> 30 done at load ~22; new `p13b_idle_check.R`: 34 callbacks and real-time token arrival while idle |
| 50 | CLI runner: 3 slots, failure/timeout isolation, usage aggregation (§5.15) | confirmed | re-run `p7`: 3.43 s at load ~22 (7.29 s at load 86-101), usage 3310/750, 3 of 5 ok |
| 51 | Agent-file loader output, `$mode` partial-match bug (§2.12, §5.16) | confirmed | re-run `p8`: identical output |
| 52 | Mode default `"auto"` (§4.3) vs `gptr_agent(mode = c("inline", ...))` and schema default `"inline"` | flagged UNCERTAIN | internal inconsistency; marked in §4.3 |

Not verifiable here (left as labelled in the text): Windows behaviour of `kill_tree()`, `supervise`, IOCP polling and CTRL+BREAK (docs only); RStudio/Positron/Jupyter behaviour of later callbacks; HTTP/2 multiplexing with `pipewait = 0` against real providers; real `claude -p` / `codex exec` streams (no paid calls); mirai 2.7.3 large-transfer speed (not installed); mori on R >= 4.5; whether R's bundled libcurl uses the threaded resolver; local Ollama's default parallelism.

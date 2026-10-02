# P-C: A workflow-first, data-science-native architecture for gptr

Proposal C of the design phase. Date: 2026-09-29. Lens: start from the R user's workflow and
the three headline benefits (in-memory compute, System 1 + System 2, the whole R ecosystem) and
work inward; every internal layer must be justified by a north-star example it enables.

Sources: `dev/spec/00-vision-brief.md` (REQ-nn), `dev/spec/01-decision-register.md` (S-n, D-nn),
`dev/spec/02-north-star-examples.md` (NS-n), `dev/plan/00-conventions.md`, and research reports
`dev/research/NN-*.md` cited as "NN §x" (their verification logs override their bodies; G5 exists
only as the digest entry and its scratch prototypes, cited as "G5"). Checks I ran for this
proposal are in `scratchpad/work/design/P-C/` (`byname.R`, `dispatch.R`, `deps.R`) and are cited as "P-C".

---

## 1. Pitch and design principles

### 1.1 Pitch

gptr turns an R script into an agent program. One file holds quoted prompts, ordinary R, typed
System 1 decisions inside `if`/`for`/`while`, and `|>` chains that steer one agent session; the
same file is the record of what the agent did and replays without a model. The agent computes on
the objects already in memory (a 5 GB Seurat object is loaded once), everything it can do is an R
function it composes in one evaluation, and everything gptr ships (providers, tools, the
permission gate, the document writer, the console) is a plugin on one versioned API. The wire
layer is gptr's own, built for interrupts, honest failures and many concurrent streams; the
context layer is built to keep provider caches warm and to spend tokens only where R cannot
compute the answer itself.

### 1.2 Principles, and what each one decides

| # | Principle | Consequence in this design |
|---|---|---|
| P1 | **The script is the program, the history and the graph** (REQ-24..26, REQ-35) | Every top-level `gptr()` call owns a delimited block of recorded code in the calling document (14 §3.1); nested calls (inside loops) get *cassettes* so a whole script replays without model calls (§4.1.7); System 1 answers are cached per element. Orchestration is R control flow; there is no workflow DSL. |
| P2 | **One gateway, one session object, one queue** (S-1, S-8) | `gptr()` returns the session environment itself. Piping appends to it; the Ctrl-C pause menu, `gptr_steer()` and the pipe all feed the *same* steering queue (G1 §4.6). Forking is only `gptr_fork()`. |
| P3 | **Everything the model can do is an R function** (S-4, S-12) | Four model-visible tools by default (`r`, `read`, `edit`, `write`, plus `ask` when a human is present). Search, shell, Python, SQL, MCP, apps, help and sub-agents are members of the gateway namespace `gptr$...` or nested `gptr()` calls, composed inside one `r` evaluation (G5, G1 §4.8). |
| P4 | **Objects stay in memory; the context holds names and budgets** (REQ-21/22, REQ-42) | Attached objects are quosures read by name; the session refers to the designated value *by name* (P-C `byname.R`); workspace summaries are budgeted (600 tokens); introspection follows the leaf/formatter discipline (12 §2.C) so nothing gptr does forces a copy of a user object. |
| P5 | **Typed decisions are R values** (REQ-20) | `gptr(q, x, model = jev)` returns `gptr_decision` (logical), `gptr_choice` (classed character) or `gptr_score` (double) with probabilities as attributes; vectorised over `x`; drops into `if`, `table()`, `==` (04 §4.5). |
| P6 | **Built-ins are plugins** (S-11) | One registry keyed by (kind, name) with 22 kinds and per-kind constructors (G1 §3.1); every built-in (`builtin:providers`, `builtin:tools`, `builtin:permissions`, `builtin:documents`, `builtin:console`, ...) is loaded by the same `ext_load()` third parties use. |
| P7 | **Token economy is measured, not hoped for** (S-12) | Frozen, cache-anchored prefix (G4); calibrated estimator (chars/4 prose, chars/2 printed R, 21 §2.8); per-request token ledger; budgets; a benchmark suite over the north-star tasks that fails on regressions (§14). |
| P8 | **Own the wire, fail honestly** (S-10, 10a) | curl-multi reactor polled with `processx::poll()` together with child pipes; normalised events; failures are events, not conditions; no httr2, no R LLM package (§8). |
| P9 | **Consent and CRAN safety by construction** (REQ-02, 13) | No writes outside `.gptr/`, `R_user_dir()` and `tempdir()`; `.gptr/` only by `gptr_init()` or interactive yes; never name `.GlobalEnv`; RNG-free ids; asks fail closed without a UI. |

### 1.3 How the lens makes gptr different from the in-session agents that already exist

corteza, btw+ellmer and agenticr already give a model the live session and file tools (10 §Q1).
The design leans on what none of them has:

| | corteza / btw / agenticr | gptr (this proposal) |
|---|---|---|
| Where code runs | hard-coded `globalenv()` (10a V-30, V-31) | the caller's frame (`parent.frame()`), so `gptr()` inside a function works on that function's objects |
| What a call returns | text or an R6 chat | the session object (piped, forked, kept in a variable) or a typed System 1 vector usable in `if` |
| History | none, or a chat log | the user's own `.R`/`.Rmd`/`.qmd`/`.ipynb` with replayable blocks and cassettes |
| Decisions | none | Jev typed decisions, cached per element, vectorised on the reactor |
| Infrastructure | ellmer/httr2 (Ctrl-C loses the partial, 10a E3) | own reactor: resumable interrupts, steer/abort, many streams |
| Tool surface | btw: ~46k characters of schema per request (10 §summary) | ~690 tokens of schema; the rest is R (`gptr$grep`, `gptr$sh`, `gptr$mcp$...`) |
| Extension | ad hoc | 22 capability kinds, versioned API, conformance checker |

---

## 2. Architecture overview

### 2.1 Layers (from the user inward)

```
+----------------------------------------------------------------------------------------+
| L6 SURFACE        gptr() gateway . gptr$ namespace . SDK verbs (gptr_step/steer/fork..) |
|                   front ends: console REPL | knitr/Quarto | JSONL (workers, RPC)          |
|                   documents: .R / .Rmd / .qmd / .ipynb blocks, cassettes, transcripts   |
+----------------------------------------------------------------------------------------+
| L5 SESSION CORE   session object + append-only store | agent loop (steer/follow-up)     |
|                   context assembly (frozen T0/T1, first message, deltas) | compaction   |
|                   permission gate (policies, modes, rules)  | usage, budgets, ledger    |
+----------------------------------------------------------------------------------------+
| L4 CAPABILITIES   (all registered as specs; looked up through the registry)             |
|   tools: r . read . edit . write . ask . grep/find/ls . bridges (sh, py, sql, app)      |
|   evaluator + workspace introspection | System 1 | MCP client/server | skills/templates |
|   sub-agent backends (inline, worker, cli) | artifact types | document formats          |
+----------------------------------------------------------------------------------------+
| L3 MODEL ACCESS   provider records + wire adapters (anthropic, openai-responses,        |
|                   openai-completions, google, typesafe-system-one, cli-claude,          |
|                   cli-codex, fake) | catalog + prices | auth (vault, .env, OAuth)       |
+----------------------------------------------------------------------------------------+
| L2 ENGINES        reactor: curl multi pool + processx::poll over curl fds and child     |
|                   pipes, timers, tool FIFO, rate limiters | process supervision         |
+----------------------------------------------------------------------------------------+
| L1 REGISTRY       registry (kind, name) . extension API . hooks/events . loader        |
|                   (transactional, lazy) . conformance (gptr_check) . API version       |
+----------------------------------------------------------------------------------------+
| L0 FOUNDATION     conditions . RNG-free ids . UTF-8/bytes I/O . JSON . schema          |
|                   validation . hashing . redaction (every sink)                        |
+----------------------------------------------------------------------------------------+
```

### 2.2 Responsibilities and allowed dependencies

| Layer | Responsibility | May call | Talks upward only through |
|---|---|---|---|
| L0 | Primitives that never know about models or sessions | base R, Imports | return values |
| L1 | Holds every capability record; runs extension factories; dispatches events with Pi's semantics (block, patch, first-decision, collect) and fail-closed rules | L0 | event dispatch to registered handlers |
| L2 | Owns all waiting: HTTP transfers, child processes, timers, the R-tool FIFO; never interprets payloads | L0 | callbacks registered by L3/L4 (`on_bytes`, `on_line`, `on_done`) |
| L3 | Turns a provider-neutral context into wire requests and wire bytes into normalised events; resolves credentials per request | L0-L2 | INFRA-02 events |
| L4 | Concrete capabilities; each is a spec in L1 | L0-L3 (and L4 peers only through the registry) | tool results, events |
| L5 | The session state machine, context, permissions, persistence | L0-L4 via the registry | agent events |
| L6 | What users type and read | L0-L5 | return values, printed output |

Rules that keep this honest:

1. **L5 never calls an L4 capability by function name.** It asks the registry
   (`registry_get("tool", "r")`, `registry_all("policy")`). This is what makes every built-in
   replaceable (S-11) and testable with fakes.
2. **Nothing below L6 prints.** Renderers subscribe to events (INFRA-27). The console, knitr and
   the JSONL front end are three subscribers of the same stream.
3. **No package-global run state** (INFRA-15). The package namespace holds the registry, the
   catalog, the vault and one process reactor (connection pools and file descriptors are process
   resources). Every run's state lives in its session. The live-session index used by
   `gptr_sessions()` holds *weak references*, so it never keeps a session or its frame alive
   (a weak reference does not keep its key alive; P-C `byname.R` also shows it serialises to
   30 bytes where a strong reference to a 40 MB environment serialises to 40 MB).
4. **Copy-safety is a cross-layer invariant.** No layer stores a user object in a list,
   environment or closure it keeps. Objects are addressed by (environment, name); values are read
   through leaf functions; the tracemem regression suite (12 §5.4) runs for every layer that
   touches user objects (L4 evaluator, introspection, S1 state building, artifact snapshots,
   `/undo`, the gateway).

### 2.3 One request, end to end (orientation for the rest of the document)

```
gptr("Fit ...", mice)                                                       (L6)
  -> capture dots as quosures; resolve identifiers; locate the calling statement in the document
  -> replay decision (block exists and fresh? return replayed session, zero tokens)
  -> new session: freeze preset, T0/T1 system blocks, tool array                    (L5)
  -> first user message: <project_instructions> <environment> <mode> <workspace> <attached> prompt
  -> agent loop: adapter$build(context) -> reactor transfer -> SSE bytes -> events    (L3/L2)
  -> tool_call r{code} -> permission gate (risk classifier, mode, rules, UI)         (L5)
  -> FIFO -> evaluator in envir (capture, plots, guard, state diff) -> tool result   (L4)
  -> steering drained after the tool-result message; next turn ...
  -> settle: append entries (JSONL), write the document block, return the session   (L6)
```

---

## 3. Package file layout

### 3.1 Areas

The convention list (00-conventions §3) is confirmed with two additions: `proc` (process
supervision shared by workers, CLI providers, MCP stdio, bridges and artifacts) and `bridge`
(polyglot helpers, G5); `ext` is split into registry, loader, hooks and plugin files. `cli` means the
subscription CLI providers, not the cli package.

### 3.2 `R/` files (108 files; one responsibility each)

| File | Responsibility |
|---|---|
| `utils-conditions.R` | `gptr_abort/warn/inform()`; conventions §5 classes; messages pass `redact()` |
| `utils-ids.R` | RNG-free ids (sha256 of time, pid, counter, content) |
| `utils-encoding.R` | UTF-8 marking, `os_bytes()`, binary-connection text I/O (C-locale safe) |
| `utils-options.R` | option defaults, human-present detection, verbosity, `on_load()` registry |
| `utils-paths.R` | project root, `gptr_user_dir()`, path classes, atomic write |
| `utils-text.R` | head 40% / tail 60% truncation to a token budget, spill files, ANSI cleanup |
| `utils-hash.R` | sha256, `canonical_json()` (radix key order), sampled fingerprints |
| `json-encode.R` | `json_encode()`, once-serialised entries, verbatim body assembly (19 §2) |
| `json-partial.R` | incremental partial-JSON scanner, throttled previews (21 §2.7) |
| `json-schema.R` | argument validation and coercion (INFRA-09); R-signature rendering |
| `ext-registry.R` | records, precedence ranks, filters, diagnostics, `gptr_registry()` |
| `ext-specs.R` | 22 constructors, `gptr_spec()`, `gptr_kind()`, `gptr_tool_result()` |
| `ext-api.R` | locked extension API object, `register_<kind>()` sugar, event bus |
| `ext-load.R` | transactional, lazy factory loading; `gptr_reload()`; stale-API errors |
| `ext-hooks.R` | event dispatch semantics; fail-closed events |
| `ext-check.R` | `gptr_check()`, API version/features, deprecation helper |
| `ext-plugins.R` | plugin packages/directories, `.claude-plugin/`, `gptr_plugins()` |
| `ext-builtins.R` | declares and loads every `builtin:*` extension through `ext_load()` |
| `proc-supervise.R` | processx children: UTF-8 pipes, `write_all()`, `kill_all()`, orphan sweep |
| `http-reactor.R` | the reactor: curl pool + `processx::poll()`, timers, tool FIFO, `later` pump |
| `http-request.R` | request spec -> curl handle (`pipewait = 0L`, layered timeouts, vault headers) |
| `http-sse.R` | vectorised byte-level SSE/NDJSON splitter (21 §2.6) |
| `http-retry.R` | error classes, capped backoff, `retry-after(-ms)`, rate limiter |
| `auth-secrets.R` | vault, `gptr_secret` handles, ambient discovery (G6) |
| `auth-redact.R` | one redactor, sink profiles, streaming hold-back (G6) |
| `auth-dotenv.R` | `gptr_env()`: `.env` parser and aliases |
| `auth-store.R` | `auth.json` store (0600, lock), keyring references |
| `auth-oauth.R` | PKCE (openssl randomness), loopback or paste callback, refresh |
| `catalog-models.R` | snapshot, merge layers, aliases, `gptr_models()` |
| `catalog-prices.R` | cost per usage record, tiers, 5 min / 1 h cache pricing |
| `provider-message.R` | messages and content blocks with provenance (INFRA-07) |
| `provider-events.R` | normalised events; linear accumulator |
| `provider-transform.R` | projection and cross-provider hand-off (INFRA-04/08) |
| `provider-registry.R` | provider records, compat flags, origin-bound credentials |
| `provider-anthropic.R` | `anthropic-messages` adapter, breakpoints, mid-conversation system messages |
| `provider-openai-responses.R` | `openai-responses` adapter, stateless replay, ChatGPT-plan filter |
| `provider-openai-completions.R` | `openai-completions` adapter + compat table (09 §3) |
| `provider-google.R` | `google-generative-ai` adapter, thought signatures |
| `provider-fake.R` | `fake` adapter, `gptr_fake_provider()` |
| `s1-types.R` | `gptr_decision/choice/score` and methods; delayed vctrs methods |
| `s1-client.R` | `typesafe-system-one` adapter; bounded rounds on the reactor |
| `s1-gateway.R` | System 1 path of `gptr()`: batch rule, `as_state()`, abstention |
| `s1-emulate.R` | emulation by structured output or logprobs (04 §4.8) |
| `s1-cache.R` | per-element decision cache (memory, then `.gptr/cache/s1/`) |
| `eval-core.R` | hand-rolled evaluator (12 §4.3) |
| `eval-plots.R` | plot recording and PNG replay (768x512) |
| `eval-guard.R` | advisory guard lists; `gptr` symbol shim |
| `env-snapshot.R` | copy-safe snapshot and diff |
| `env-describe.R` | `gptr_describe()` and methods (incl. Seurat, SCE, data.table, Arrow, DBI) |
| `env-history.R` | task-callback log of the user's top-level expressions |
| `tool-contract.R` | never-throw dispatcher, validation, execution modes |
| `tool-namespace.R` | `gptr$` namespace methods; closures generated from schemas |
| `tool-r.R` | the `r` tool (code, record, note, timeout) |
| `tool-read.R` | `read` / `gptr$read()`: decoding, windows, images, large-file index |
| `tool-write.R` | `write` / `gptr$write()`: atomic, encoding- and EOL-preserving |
| `tool-edit.R` | `edit` / `gptr$edit()`: multi-edit, fuzzy fallback, patch envelopes, diff |
| `tool-walk.R` | pruned walker, gitignore engine, glob-to-PCRE |
| `tool-grep.R` | `gptr$grep()` (opt-in `grep` tool): raw prefilter, PCRE, early stop |
| `tool-find.R` | `gptr$find()`, `gptr$ls()` (opt-in tools): radix sorting |
| `tool-ask.R` | `ask` tool with UI backends and non-interactive defaults |
| `perm-classify.R` | `gptr_risk()`: R, shell, SQL and Python classifiers |
| `perm-gate.R` | policies, modes, rules, persistence, budgeted `/undo` |
| `perm-ui.R` | UI backends (console, none, scripted, rpc); one-line prompt |
| `agent-loop.R` | Pi's two loops as a steppable state machine; queues |
| `agent-run.R` | run states for the reactor; nested runs |
| `agent-recovery.R` | overflow, compact-and-retry, agent-level retry |
| `prompt-sections.R` | section registry, presets, freeze, section patches |
| `prompt-context.R` | context blocks, first user message, per-turn deltas |
| `prompt-instructions.R` | AGENTS.md/CLAUDE.md root to cwd, then vignette.Rmd (text) |
| `prompt-cache.R` | breakpoints, prefix guard, request assembly by concatenation |
| `prompt-compact.R` | trigger, in-conversation checkpoint, extracted state (G4 §4.4) |
| `prompt-tokens.R` | calibrated estimator, image tokens, token ledger |
| `session-object.R` | `gptr_session`, accessors, print, fork |
| `session-store.R` | Pi v3 JSONL tree store, resume, fork files, lock |
| `session-usage.R` | usage records, `gptr_usage()`, budgets |
| `gptr-gateway.R` | `gptr()` dispatch, dot facts, prompt selection, interpolation |
| `gptr-resolve.R` | identifier NSE (alias wins, `!!`) |
| `gptr-sdk.R` | SDK verbs, `gptr_last/return/prob/jobs` |
| `gptr-config.R` | settings layers, `gptr_config()`, `gptr_init()`, trust, egress consent |
| `gptr-setup.R` | `gptr_providers()`, `gptr_login/logout()`, doctor checks |
| `console-repl.R` | REPL, input grammar, `!`/`!!`, `@mentions`, banner |
| `console-render.R` | chunk-invariant markdown renderer, tool lines, status line |
| `console-interrupt.R` | interrupt policy with the `resume` restart |
| `console-commands.R` | slash commands |
| `doc-locate.R` | locate the calling statement (srcref, source, knitr, Quarto, IDE, Rscript, IRkernel) |
| `doc-blocks.R` | block grammar, ownership, idempotent upsert |
| `doc-write.R` | atomic I/O, conflict checks, deferred Rscript writes, IDE backends |
| `doc-formats.R` | `.R`, Rmd/qmd chunks, ipynb serializer, transcripts |
| `doc-replay.R` | replay modes, S2 cache, cassettes, `gptr_source/cache/blocks()` |
| `doc-knitr.R` | `knit_print`, stale-chunk hooks, optional `{gptr}` engine (off) |
| `skill-discover.R` | skill scan, budgeted catalog, preload |
| `skill-templates.R` | prompt templates, `/name args` |
| `subagent-defs.R` | agent files (.gptr, .claude, .codex, .pi); tool-name map |
| `subagent-backends.R` | `inline`, `worker`, `cli` backends |
| `subagent-team.R` | teams, fan-out, `gptr_parallel()`, `gptr_map()`, exports |
| `subagent-worker.R` | worker script, JSONL front end, stdin answers |
| `mcp-client.R` | client for both eras; stdio and Streamable HTTP |
| `mcp-config.R` | `mcp.json`, other harnesses' configs, TOML reader |
| `mcp-namespace.R` | `gptr$mcp$<server>$<tool>()`, budgeted catalog, BM25 search |
| `mcp-server.R` | dispatcher, Claude `sdk` transport, HTTP, `gptr_mcp_serve()` |
| `cli-common.R` | external-agent adapter pieces, CLI discovery, notices |
| `cli-claude.R` | `cli-claude`: stream-json, control protocol, in-process MCP |
| `cli-codex.R` | `cli-codex`: `codex exec --json`, MCP via `-c`, sandbox mapping |
| `bridge-sh.R` | `gptr$sh/script/bg/jobs/out()` (G5) |
| `bridge-lang.R` | `gptr$py/sql/knit()`; the `interpreter` kind |
| `artifact-app.R` | `gptr$app()`: versions, snapshots, `run.R`, validation ladder |
| `artifact-registry.R` | `gptr_artifacts()`, open, stop, lazy orphan sweep |
| `zzz.R` | `.onLoad`/`.onUnload` running the `on_load()` registry |

### 3.3 `inst/`

```
inst/extdata/models.json.gz        pruned models.dev snapshot + prices, schema_version (09 §4, ~51 KB)
inst/extdata/risk-functions.csv    classifier function table (package, function, level, category)
inst/gptr/skills/high-performance-r/SKILL.md (+ references/)   (19 §3)
inst/gptr/skills/shiny-bslib/SKILL.md                          (17 house style)
inst/gptr/skills/gptr-orchestration/SKILL.md                   (how to write sub-agents, S1 loops)
inst/gptr/agents/reviewer.md, explorer.md                      (small defaults, minimal preset)
inst/gptr/prompts/explain.md, review.md                        (templates)
inst/templates/vignette.Rmd, settings.json, gitignore          (used by gptr_init())
inst/scripts/worker.R, artifact-run.R                          (child-process entry scripts)
inst/COPYRIGHTS                                                (Pi MIT; models.dev MIT; ideas from ellmer/tidyllm credited)
```

### 3.4 Tests and shipped test infrastructure

```
tests/testthat/test-<area>-<topic>.R            one per R file
tests/testthat/setup.R                          redirect R_USER_*_DIR, blank keys, gptr.interactive = FALSE,
                                                gptr.quiet = TRUE, OMP_THREAD_LIMIT = 2, GPTR_REPLAY = "replay"
tests/testthat/helper-fake.R                    fake provider scripts
tests/testthat/helper-mock-server.R             base-R SSE mock (serverSocket), started with processx, skip_on_cran
tests/testthat/helper-tracemem.R                fresh-process copy checks (skip without capabilities("profmem"))
tests/testthat/fixtures/sse/                    anthropic_*.sse, openai_*.sse, gemini_*.sse (incl. thinking,
                                                redacted, encrypted reasoning, parallel tools, overload, truncation)
tests/testthat/fixtures/cli/                    claude_call2.ndjson (redacted), codex_exec.jsonl, fake_cli.R
tests/testthat/fixtures/mcp/                    stdio server script (both eras), config fixtures written at test time
tests/testthat/fixtures/docs/                   .R, .Rmd, .qmd, .ipynb (incl. Python-written floats)
tests/testthat/fixtures/jev/                    live-shaped answers from 04a (noul, choice, score, errors)
dev/bench/tokens/                               token-efficiency benchmark (§14.5), excluded from the build
dev/bench/perf/                                 grep/read/SSE/diff benchmarks from 11, 19, 21
vignettes/*.Rmd.orig -> *.Rmd                    precomputed: getting-started, script-as-history, system-one,
                                                extending-gptr, token-efficiency
```

---

## 4. Exported API

73 exports: `gptr` plus 72 `gptr_*` names (D-28; none collides, G1 §4.7). The gateway object also
carries a namespace, `gptr$<member>`, which is how model-written code and users reach tools and
bridges without more exports. Every exported function forwarding `...` uses dot-prefixed formals
where a user name could be captured (05 §4).

### 4.1 `gptr()`, the gateway

```r
gptr = function(..., model = NULL, mode = NULL, skills = NULL, plugins = NULL,
                extensions = NULL, tools = NULL, agents = NULL, parallel = NULL,
                choices = NULL, levels = NULL, threshold = 0.5, uncertain = NULL,
                prompt = NULL, envir = parent.frame(), background = FALSE,
                budget = NULL, replay = NULL, .opts = list(), .run = TRUE,
                .stdin = FALSE)
```

`gptr` is a closure with class `c("gptr_gateway", "function")` and S3 methods `$`, `[[`,
`.DollarNames` and `print` (verified to pass `R CMD check` codoc in G5's toy package
`gwtoy.Rcheck`). Calling it runs the agent; `gptr$name` reaches the namespace (§4.2).

**Arguments.** `...`: at most one leading session (continuation), the prompt, and context objects
(unnamed ones labelled by their expression, named ones by name). `model`, `mode`, `skills`,
`plugins`, `extensions`, `tools` take bare identifiers (§4.1.3). `agents`: named list of agent
definitions (`agent()` works inside it). `parallel = n`: fan a list/vector context out over `n`
concurrent sub-agents. `choices`, `levels`, `threshold`, `uncertain`: System 1 answer shape.
`envir`: where code runs and objects persist (D-04). `background = TRUE`: return at once, run while
the console is idle (needs `later`). `budget = list(tokens =, cost =, turns =)`. `replay`: document
replay mode. `.opts`: rare switches (`thinking`, `max_turns`, `context` = `"none"|"names"|"summary"`,
`record`, `interpolate`, `timeout`, `min_confidence`, `output = "factor"`, `system`, `preset`,
`cache_ttl`). `.run = FALSE`: build the session with the prompt queued (SDK). `.stdin = TRUE`: drive
the console from piped input (18 §4.2).

#### 4.1.1 Dispatch algorithm

```
1  Capture:   dots = rlang::enquos(...); ids = enquo(model), enquo(mode), ... (12 §2.D2)
2  Facts:     for each dot, by name and without forcing (12 §5.3 dot facts):
                is it a gptr_session / gptr_team? a string literal? a length-1 character value?
3  Session:   the first unnamed dot that is a session is the continuation target `s`.
4  Prompt:    prompt= if given; else the first unnamed string literal; else the first unnamed
              length-1 character value that is not a session (12 §2.D3). Literal prompts get
              {identifier} interpolation (4.1.4). Two unnamed literals -> warning.
5  Context:   every other dot -> context quosure with a label (name or deparsed expression).
6  Model:     resolve `model` (4.1.3). If the resolved model is a classifier (System 1):
                -> s1_dispatch(prompt, context or as_state(s), choices, levels, ...) and RETURN a
                   typed vector (4.1.5). No session is created.
7  Nested?    if a run is active on this call stack (the r tool is evaluating model code):
                -> child session linked to the running one (depth + 1, mode inherited and only
                   tightened, usage rolled up, no document block). Continue at 11.
8  No prompt: if no prompt:
                s given, human present      -> REPL on s                     (returns s invisibly)
                nothing given, human present -> REPL on a new session        (returns it invisibly)
                otherwise                    -> gptr_error_noninteractive (18 §4.2)
9  Team:      agents given -> team session with one child per agent (4.1.6).
10 Fan-out:   parallel = n with one list/vector context -> fan-out session.
11 Document:  top-level call? doc_locate() the statement; decide replay (14 §4.4.2):
                replay -> return a replayed session (zero tokens; team/fan-out texts come from
                the S2 cache); the block code runs next as R.
              nested call with a cassette hit -> cassette replay (4.1.7).
12 Target:    s given -> continue s: if s is running -> gptr_steer(s, prompt) and return s;
              if idle -> append a follow-up turn. Otherwise create a session (unless 9/10 did).
13 Run:       .run = FALSE -> return s with the prompt queued.
              background = TRUE -> register the run with the reactor's idle pump; return s.
              else run to settlement under the interrupt policy (teams and fan-outs run all
              children on the reactor); write the block (for teams: `## agent <name>: ...`
              notes and the exported assignments); return s (invisibly if the answer was
              already streamed to the console, 12 §3.10).
```

#### 4.1.2 Call shapes (all from the north star)

| Call | Resolves to | Returns |
|---|---|---|
| `gptr()` | step 8: REPL, new session | the session, invisibly on `/exit` |
| `s \|> gptr()` | step 8: REPL on `s` | `s` |
| `gptr("prompt", mice)` | new session; context `mice` | session (print shows the answer) |
| `mice \|> gptr("prompt")` | same (data-first pipe: first arg is not a session) | session |
| `gptr("a") \|> gptr("b") \|> gptr("c", model = opus)` | one session, three turns, model switch with hand-off | the same session |
| `qc \|> gptr("Use 15% ...")` | continuation; follow-up if idle, steering if running | `qc` |
| `gptr_fork(qc) \|> gptr("Try 10%")` | new session (copied lineage) | the fork |
| `gptr("Is ...?", abstracts, model = jev)` | System 1 | `gptr_decision` vector |
| `gptr(q, samples$description, model = jev, choices = c(...))` | System 1 choice | `gptr_choice` vector |
| `s \|> gptr("Did it succeed?", model = jev)` | System 1 on `as_state(s)` | `gptr_decision` |
| `gptr(task, model = if (hard) opus else haiku, mode = auto)` | expression evaluated in the alias mask | session |
| `gptr("Review ...", agents = list(stats = agent(model = opus), ...))` | team | team session (`$stats`) |
| `gptr("Summarise this cohort", cohorts, parallel = 4)` | fan-out | fan-out session |
| `res = gptr("task", data, model = gemini)` inside `r` | nested child session | child session |

#### 4.1.3 Identifier resolution (D-07)

Capture with `rlang::enquo()` (12 §2.D2: base `substitute()` resolved forwarded dots to the wrong
variable). Resolution (12 §3.11; P-C `dispatch.R`):

| Expression | Result |
|---|---|
| `NULL` | default from settings |
| string constant | itself (`model = "opus"`) |
| symbol that is a **known identifier** (catalog alias, registered model/router, discovered skill, plugin, extension or agent, mode name) | the name: **the alias wins over a same-named variable**, as in `library(pkg)` (12 D1, 10 Q4), so attached packages exporting `claude`, `codex`, `gemini`, `plan` cannot hijack it |
| unknown symbol bound to a character value | the value (`m = "opus"; gptr(t, model = m)`) |
| unknown symbol bound to anything else | classed error: "`mice` is a variable of class <data.frame>, not a model name" |
| unknown unbound symbol | the literal name, validated later with `adist()` suggestions (09) |
| `!!x` | the value of `x` (escape for shadowed aliases) |
| `c(a, "b")` | element-wise |
| other calls (`if (hard) opus else haiku`) | evaluated in a mask of known identifiers over the caller |

A shadowing character variable with a different value triggers a once-per-session notice
("used the alias; write !!sonnet"). Block headers always get canonical ids, never aliases (09).

#### 4.1.4 Prompt interpolation (resolves NS-11 against 12 §2.D4)

NS-11 writes `gptr("Cluster {cl} has ambiguous markers ({top}) ...")` in a loop; 12 advised against
automatic `{}` interpolation (prompts contain code, JSON, LaTeX). Decision: interpolate **only
`{identifier}` in literal prompts**, only when the identifier is bound in `envir` to an atomic
vector of at most 50 elements (joined with `", "`); `{{`/`}}` escape; `.opts$interpolate = FALSE`
disables it. JSON, code and unbound names are untouched; the one verified false positive is LaTeX
with bound single letters (`\frac{x}{y}`; P-C `dispatch.R`), and the interpolated prompt is shown
in the transcript. Blocks hash the template (stable when data change, 14 §7); cassettes key on the
interpolated text. Token effect: ~10 tokens instead of ~60-120 for attaching `cl` and `top`.

#### 4.1.5 System 1 path

Batch rule (04 §4.7): atomic vector -> one state per element (names kept); unnamed list -> per
element; data frame -> per row; named list -> one state; `I(x)` -> exactly one state (keeps a
`while()` condition scalar). Type: `choices` -> choice, `levels` -> score, else `noul` (never the
public name `bool`, 04a). The S1 cache is checked per element; misses are deduplicated and sent on
the reactor, at most 8 at a time, in bounded rounds that resubmit only failures (04 §4.7; never
`httr2::req_perform_parallel`, which retries 429/503 without bound). Abstention is **off by
default** (`if()` never sees `NA`); `.opts$min_confidence` maps the uncertain band to `uncertain`
(`NA`, `TRUE`/`FALSE`, `"stop"`, or `function(state, answer)` to escalate to System 2 or the user),
merging D-06's `na_below`/`stop_below`. Choice labels that look logical (`"TRUE"`, `"F"`) warn
(04 verifier). Without a Jev key: gateway keys (OpenRouter, Vercel) if present; else an interactive
one-time offer to emulate on the small model (marked uncalibrated); non-interactive -> classed
error. Cost: ~250-280 input tokens per request at $0.042/M (04 §2.5); 20 items ~$0.0002, ~0.4 s.

#### 4.1.6 Sub-agents from the gateway

`agents =` is evaluated in a mask where `agent` is `gptr_agent` (15 §4.3; not exported, G1 §4.7).
Backend `"auto"` = inline, except `cli` for CLI-only models (`codex`, `claude_code`). `parallel = n`
runs one inline child per element, `n` at a time, each seeing its element as a lazy quosure
(`cohorts[["A"]]`). `background = TRUE` (experimental; `later` in Suggests) runs on the reactor's
idle pump; piping into the running session enqueues steering; `gptr_wait(s)` blocks.

#### 4.1.7 Replay for nested calls: cassettes

14 never records calls nested in loops or functions, so NS-11's inner calls would run live on every
re-source. A **cassette** (`.gptr/cache/s2/cassettes/<sha256>.json`) is keyed by (document path,
sha256 of the call template and its ordinal, interpolated prompt, class/dim/names digest of the
context) and holds the final text, the recorded code chunks, the designated value name and usage.
In `auto`/`replay` a hit returns a replayed session and **evaluates the recorded chunks in
`envir`** (code that already ran under the user's mode in this project; 13 proposes that recorded
code in a user-sourced document needs no new permission); a miss runs live (auto) or errors
(replay). `gptr_cache("show", key)` and `gptr_blocks()` expose cassettes; they are gitignored by
default (C-31) and redacted at ingress (G6).

### 4.2 The gateway namespace `gptr$...`

Members are **tools with `exposure = "r"`** (G1 row 5) whose R function is either written by hand
(`fun =`) or generated from the JSON schema. Model-written code in the `r` tool and user code use the
same calls; they are recorded verbatim in documents. Calls made from model code pass through the
permission gate as nested calls (06 §4); calls typed by the user are the user's actions.

| Member | Signature | Returns / prints |
|---|---|---|
| `read` | `gptr$read(path, offset = NULL, limit = NULL)` | `gptr_lines` (character + attributes); Pi-format print |
| `write` | `gptr$write(path, content)` | invisible path |
| `edit` | `gptr$edit(path, edits, replace_all = FALSE)` | `gptr_patch` (diff) |
| `grep` | `gptr$grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, literal = FALSE, context = 0, limit = 100, output = "content")` | `gptr_matches` data frame (file, line, text); budgeted print |
| `find` | `gptr$find(pattern, path = ".", sort = "path", type = "file", limit = 1000)` | `gptr_files` data frame (path, size, mtime) |
| `ls` | `gptr$ls(path = ".", sort = "name", long = FALSE)` | `gptr_files` |
| `sh` | `gptr$sh(cmd, input = NULL, wd = ".", timeout = 120, env = NULL, merge = FALSE, check = FALSE)` | `gptr_cmd` ($stdout, $stderr, $status); head+tail print within 1,500 tokens (G5) |
| `script` | `gptr$script(path, args = character(), interpreter = NULL)` | `gptr_cmd` |
| `bg`, `jobs` | `gptr$bg(cmd, name = NULL)`, `gptr$jobs(kill = FALSE)` | `gptr_job` environment ($read, $wait, $write, $kill) |
| `out` | `gptr$out(id, lines = NULL)` | full output of a truncated result (ids appear in truncation notices) |
| `py` | `gptr$py(code, name = NULL, max_rows = 10)` | `gptr_py` ($value converts to R); reticulate (Suggests) |
| `sql` | `gptr$sql(query, name = NULL, con = NULL, n = 10)` | data frame; duckdb registration of data frames, else the DBI connection in scope |
| `knit` | `gptr$knit(engine, code)` | output of any knitr engine |
| `app` | `gptr$app(id, data = NULL, title = NULL, kind = "shiny", check = "session", launch = interactive())` | `gptr_artifact`; URL, checks and a screenshot image for the model |
| `help` | `gptr$help(topic, package = NULL, budget = 800)` | help text via `tools::Rd2txt`, budgeted (20 §5 r_native_tools) |
| `search` | `gptr$search(words, limit = 8)` | BM25 over deferred tools, MCP tools and skills (06 §4) |
| `mcp` | `gptr$mcp$<server>$<tool>(...)` | R values (lists/data frames); lazy connect |
| `describe` | `gptr$describe(x, budget = 300)` | same as `gptr_describe()` |

The `$` method errors helpfully for unknown members and lists what exists. `gptr$x = value` errors
(`$<-.gptr_gateway`). When model code is evaluated in an environment from which the symbol `gptr`
is not visible (the user called `gptr::gptr()` without attaching), the evaluator rewrites calls
headed by `gptr`/`gptr_return` to `gptr::` before evaluation (`eval-guard.R` shim); the recorded
code keeps the original text, and transcripts start with `library(gptr)`.

### 4.3 The other exports

**Setup and status**

- `gptr_init(path = NULL, instructions = TRUE, gitignore = TRUE, commit_cache = FALSE)`: creates
  `.gptr/` (vignette.Rmd template, settings.json, .gitignore, skills/, agents/, prompts/). `path =
  NULL` proposes the detected project root and asks yes/no when a human is present; without a human
  it errors and requires a path (13 §2: consent; NS-9 calls it with no argument, which works
  interactively). Offers `^\.gptr$` for `.Rbuildignore` in package sources.
- `gptr_config(..., .scope = c("session", "project", "user"))`: reads or sets settings; bare
  identifiers accepted (`gptr_config(model = sonnet, mode = manual)`). Project scope may only
  tighten security settings (18 §4.7).
- `gptr_env(path = ".env", aliases = NULL, set_env = TRUE, override = FALSE, quiet = FALSE)`:
  own `.env` parser (BOM, CRLF, `export`, quotes, multi-line, hyphenated names); `aliases = NULL`
  uses the built-in table, extended by plugins through `register_env_alias()` (G6), mapping
  `jev-key`, `JEV_KEY`, `JEV_API_KEY`, `TYPESAFE_KEY` to `TYPESAFE_API_KEY`; registers every value
  in the vault; exports canonical names only; never prints values (G6, REQ-13).
- `gptr_login(provider, method = NULL)` / `gptr_logout(provider)`: interactive OAuth or key entry
  (`"chatgpt"` = Sign in with ChatGPT preview, `"openrouter"`, MCP servers by URL); tokens in the
  credential store (0600, lock).
- `gptr_providers(check = FALSE)`: data frame of providers with credential source (handle and
  fingerprint only), reachability (`check = TRUE`), CLI versions and plan status.
- `gptr_models(query = NULL, provider = NULL, refresh = FALSE, reset = FALSE, discover = FALSE)`:
  searches the merged catalog; refresh only on request into `R_user_dir("gptr", "cache")` (09 §4).
- `gptr_trust(path = ".", trust = NULL)`: shows or records the project trust decision that gates
  project settings, extensions, MCP configs and agent files (05, 16).
- `gptr_permissions(allow = NULL, ask = NULL, deny = NULL, remove = NULL, scope = "session")`:
  shows and edits rules in the grammar of 18 §3.7.

**Discovery**

- `gptr_skills(scope = "all")`, `gptr_agents(scope = "all")`, `gptr_plugins(installed = FALSE)`:
  data frames of discovered skills, agent definitions and plugins with their token cost column.
- `gptr_mcp(server = NULL, tools = FALSE)`: servers (own and imported from other harnesses), era,
  status, tool counts; `tools = TRUE` lists signatures.
- `gptr_mcp_add(name, command = NULL, args = NULL, url = NULL, env = NULL, headers = NULL,
  exposure = "r", scope = "user")` and `gptr_mcp_remove(name, scope = "user")`.
- `gptr_mcp_serve(tools = c("r", "read", "edit", "write"), port = NULL, envir = parent.frame())`:
  serves the live session to external agents over loopback HTTP with a bearer token (httpuv,
  Suggests); returns a handle with `$url`, `$token_env`, `$stop()`.

**Documents**

- `gptr_doc(path = NULL, format = NULL)`: binds the console session to a document (explicit
  consent to write it) or shows the current binding.
- `gptr_source(file, replay = "auto", envir = parent.frame(), ...)`: sources a gptr script so
  stale or live blocks regenerate without executing the old block (14 §4.4.2).
- `gptr_blocks(file)`: data frame of blocks and cassettes (id, prompt hash, state fresh/stale/
  user-edited, model, date, tokens, cost).
- `gptr_cache(action = c("list", "show", "clear", "prune"), kind = c("s1", "s2", "all"), key = NULL)`.

**Artifacts**

- `gptr_artifacts()`: data frame of artifacts (id, version, status, url, pid); sweeps orphans.
- `gptr_artifact_open(id, version = NULL)`: relaunches if needed and opens the viewer.
- `gptr_artifact_stop(id = NULL)`: stops one or all (interrupt, 3 s grace, kill tree).

**Values and introspection**

- `gptr_usage(x = NULL, by = c("session", "agent", "model", "route"), detail = FALSE)`: sums usage
  records of a session, team, list of sessions or (x = NULL) every live session and S1 call;
  `detail = TRUE` returns the per-request token ledger.
- `gptr_last()`: the most recent session in this R process (including an aborted one).
- `gptr_return(x)`: inside a run, designates the result. A symbol bound in the run's `envir` is
  stored **by name** (P-C `byname.R`: no copy on the user's next edit); anything else is stored as a
  value. Errors outside a run.
- `gptr_prob(x, what = c("prob", "confidence", "probabilities"))`: System 1 accessor.
- `gptr_describe(x, budget = 300L, ...)`: S3 generic; methods return at most `budget` tokens of lines,
  never force promises or do I/O (12 §3.9).
- `gptr_risk(code, envir = NULL, root = NULL)`: advisory static classifier; returns flagged calls
  with levels 0-4 and categories; "not a security boundary" (18 §2.5).
- `gptr_packages(probe = FALSE)`: installed-package capability table used by `<r_env>` (19 §3.2).

**Session SDK** (G1 §4.6; every verb takes the session)

- `gptr_step(s)`: exactly one model turn including its tool calls; returns `s`.
- `gptr_wait(s, timeout = Inf)`: runs `s` (or a list of sessions) to settlement on the reactor.
- `gptr_steer(s, text, follow_up = FALSE)`: enqueues steering (delivered after the next complete
  tool-result message, INFRA-12) or a follow-up.
- `gptr_cancel(s)`: aborts: cancels transfers, kills child trees, records the partial honestly.
- `gptr_fork(s, at = NULL)`: new session whose store file copies the path to `at` (default leaf);
  never shares listeners, queues, connections or processes (INFRA-14).
- `gptr_on(s, event, handler)`: session-scoped hook at rank 0; returns an `off()` function.
- `gptr_parallel(..., .list = NULL, max_active = 8, on_error = c("return", "stop"))`: runs deferred
  `gptr()` calls concurrently; returns a team session.
- `gptr_map(.x, prompt, ..., model = NULL, agent = NULL, max_active = 4, backend = "auto")`: the
  function behind `parallel =`.
- `gptr_sessions(project = TRUE)` / `gptr_resume(id)`: list stored sessions; rebuild one from its
  JSONL leaf-to-root path (envir = caller).
- `gptr_jobs(kill = FALSE)`: background runs and helper jobs.

**Extension API** (G1 §4.5)

- `gptr_api_version()` -> `package_version("1.0")`; `gptr_api_features()` -> character.
- `gptr_register(spec, scope = "session")`: top-level registration (rank 3 for user scope).
- `gptr_registry(kind = NULL, diagnostics = FALSE)`: records with rank, source, state (lazy,
  active, overridden, disabled) and estimated token cost.
- `gptr_reload()`: re-discovers resources; bumps the generation so stale API objects error.
- `gptr_check(x, error = FALSE)`: conformance for a spec, factory, plugin package or adapter (with
  wire fixtures); returns a `gptr_check` data frame.
- `gptr_fake_provider(script, name = "fake")`: registers a scripted provider for tests and examples.
- `gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)`.
- `gptr_spec(kind, name, ...)`: spec for a plugin-defined kind.

**Spec constructors** (contracts in §13; all return `c("gptr_<kind>", "gptr_spec")` lists)

| Constructor | Signature |
|---|---|
| `gptr_tool` | `(name, description, parameters = NULL, execute = NULL, fun = NULL, annotations = list(), exposure = c("direct", "r", "deferred", "hidden"), execution = c("sequential", "concurrent"), risk = NULL, snippet = NULL, guidelines = NULL, output_tokens = NULL, record = TRUE, replay_safe = FALSE)` |
| `gptr_provider` | `(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(), type = c("chat", "classifier", "cli"), headers = list(), discover = NULL)` |
| `gptr_adapter` | `(api, transport = c("http_sse", "http_ndjson", "http_json", "process_jsonl", "inprocess"), build, parse = NULL, stream = NULL, classify = NULL, capabilities = list())` |
| `gptr_router` | `(name, route, description = NULL)` |
| `gptr_model` | `(id, provider, context = NULL, max_output = NULL, reasoning = NULL, input = "text", prices = NULL, aliases = NULL, ...)` |
| `gptr_mcp_server` | `(name, command = NULL, args = NULL, url = NULL, env = NULL, headers = NULL, exposure = "r", tool_exposure = list(), timeout = 60, protocol = NULL)` |
| `gptr_skill` | `(path, name = NULL, description = NULL)` |
| `gptr_prompt_template` | `(name, text, description = NULL, argument_hint = NULL)` |
| `gptr_command` | `(name, handler, description = NULL, complete = NULL)` |
| `gptr_hook` | `(event, handler, matcher = NULL)` |
| `gptr_policy` | `(name, check, description = NULL)` |
| `gptr_context_block` | `(name, provide, placement = c("turn", "first", "system"), budget = 300L)` |
| `gptr_compactor` | `(name, should, compact)` |
| `gptr_doc_format` | `(name, ext, locate, render, write)` |
| `gptr_artifact_type` | `(name, build, check, launch, stop)` |
| `gptr_backend` | `(name, start, poll, cancel, capabilities = list())` |
| `gptr_agent` | `(name = NULL, description = NULL, model = NULL, tools = NULL, skills = NULL, system = NULL, backend = "auto", preset = "minimal", max_turns = NULL, mode = NULL, objects = NULL, export = NULL, returns = NULL, file = NULL)` |
| `gptr_ui` | `(name, select, input, questions, notify, has_ui)` |
| `gptr_frontend` | `(name, run)` |
| `gptr_setting` | `(name, default, description = NULL, scope = c("both", "user"), validate = NULL)` |
| `gptr_prompt_section` | `(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L)` |
| `gptr_kind` | `(name, validate, resolve = c("first", "all"))` |

---

## 5. Core data structures

Mutable things are environments with an S3 class; immutable values are classed lists or base-typed
S3 vectors (D-02; G1 §4.3 measured closure-in-locked-env method calls at 1.6-1.9 µs vs 3.8-4.5 µs
for R6, and object creation 3-5 µs vs 47-76 µs for `R6$new()`).

### 5.1 The session (`gptr_session`, an environment; reference semantics per S-8)

| Field | Type | Meaning |
|---|---|---|
| `id` | chr | `"s"` + 10 hex (RNG-free) |
| `kind` | chr | `"chat"`, `"team"`, `"fanout"`, `"child"`, `"replayed"` |
| `parent_id`, `fork_of`, `depth` | chr, chr, int | lineage; `depth` 0 for top level |
| `envir` | environment | where code runs (strong reference; the index of live sessions is weak) |
| `model`, `thinking` | chr | canonical `provider/id`; thinking level clamped per model (03 §2.6) |
| `mode`, `rules` | chr, list | `plan`/`manual`/`edits`/`auto`; session allow/ask/deny rules |
| `status` | chr | `idle`, `queued`, `running`, `waiting_user`, `waiting_children`, `done`, `error`, `aborted`, `budget`, `max_turns` |
| `frozen` | list | `preset`, `t0` (text), `t1` (text), `tools_json` (once-serialised tool array), `tool_names` |
| `entries` | list | append-only transcript entries (5.2); each carries its once-serialised JSON per (api, same-model flag) |
| `leaf_id` | chr | current leaf of the tree |
| `queues` | list | `steer`, `follow_up` (FIFO lists of user messages with `source`) |
| `value_name` / `value_box` | chr / list | designated result: a name in `envir`, or a boxed fresh value |
| `usage` | data frame | one row per request (5.5), children included by reference |
| `budget`, `turns`, `max_turns` | list, int, int | limits |
| `children` | named list | child sessions (team members, fan-out elements, nested calls) |
| `doc` | list | document binding: `path`, `format`, `site` (statement range, ordinal), `blocks` |
| `store` | list | JSONL path, open `ab` connection, lock path |
| `snapshot` | data frame | last workspace snapshot (5.8) |
| `listeners` | list | session-scoped hooks (rank 0) |
| `signal` | environment | `aborted` (lgl), `reason`; checked by transport and tools |
| `plan` | chr | pending plan text (plan mode, §9.4) |
| `replayed`, `block` | lgl, chr | set for replayed sessions |
| `ctx` | `gptr_ctx` | the object extension handlers receive (G1 §3.3) |

Public accessors through `$.gptr_session`: `text` (last final assistant text; `NA` before a turn),
`value` (resolves `value_name` with `get0(name, envir, inherits = FALSE)` or returns `value_box`),
`usage` (summed), `history` (data frame view: turn, role, text preview, tools, tokens), `messages`,
`model`, `mode`, `status`, `id`, `turns`, `cost`, and child names for teams (`reviews$stats`).
`print()` shows the last answer plus a dim footer (`status . model . turns . tokens . cost . id`);
`format()`/`as.character()` return the text. `$<-` is refused (state changes go through verbs). Fan-out sessions
also have `[[` by element and `as.character()` returning the named text vector.

### 5.2 Messages and content blocks (INFRA-07)

Transcript entries follow Pi v3 (header line, then `{type, id, parentId, timestamp, ...}`; 02 §2.11)
with gptr `custom` entries. Message entries hold one of:

```r
msg_user(content, source = c("prompt", "steer", "follow_up", "context", "passthrough"))
msg_assistant(content, api, provider, model, response_id = NULL, usage = NULL,
              stop_reason = c("stop", "length", "tool_use", "aborted", "error", "refusal", "pause"),
              error_message = NULL)
msg_tool_result(tool_call_id, tool_name, content, is_error = FALSE, details = NULL)
```

Content blocks (plain lists, class `gptr_block_<type>`):

| Block | Fields |
|---|---|
| `text` | `text`, `signature` (opaque, optional) |
| `thinking` | `thinking`, `signature`, `redacted` (lgl), `data` (redacted payload, verbatim) |
| `image` | `mime`, `data` (base64 without newlines), `path` (optional local copy), `width`, `height` |
| `tool_call` | `id` (provider id verbatim, e.g. `call_id\|item_id`), `name`, `arguments` (list), `raw_arguments` (chr), `thought_signature` |
| `opaque` | `provider`, `api`, `json` (a verbatim JSON string: encrypted reasoning items, `phase`, server tool blocks), replayed byte for byte to the same model only |

`details` of a tool result never reaches the model; it carries the R-side record (code, created/
modified/removed objects, plots, warnings, the eval status). Custom entry types:
`model_change`, `mode_change`, `compaction` (summary, `first_kept_id`, extracted state),
`doc_block` (14 §3.6), `replay`, `decision` (S1 summary), `subagent`, `artifact`, `label`,
`section_patch`, `cache_break`.

### 5.3 Tool definition and result

A tool spec is `gptr_tool(...)` (§4.3). Internally the dispatcher adds: `schema_json`
(once-serialised, sorted keys), `r_signature` (one line: `grep(pattern: string, path?: string,
...)  # first sentence`), `token_cost` (estimated). Execution contract:
`execute(input, ctx)` returns `gptr_tool_result()` or character; the R-callable `fun` returns an R
value whose `print()` is budgeted.

```r
gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)
# -> list(content = list(<text block>, <image blocks>...), details, is_error,
#         value (R-side only), spill = <path or NULL>, truncated = <lgl>)
```

### 5.4 Events

`list(type, session_id, run_id, agent, turn, time, ...)`; delta-only for streaming (02 §4.4).
Provider layer (INFRA-02): `start`, `text_start|delta|end`, `thinking_start|delta|end`,
`toolcall_start|delta|end` (with a throttled partial-argument preview), `done(reason)`,
`error(reason, partial, condition_class)`. Agent layer: `agent_start|end|settled`,
`turn_start|end`, `message_start|update|end`, `tool_execution_start|update|end`, `queue_update`,
`retry_start|end`, `compaction_start|end`. gptr events (G1 §3.2): `permission_request`, `decision`,
`document_write`, `subagent_start|end`, `artifact_start|stop`, `budget_exceeded`, `route`,
`model_select`, plus `cache_break` (G4) and `bridge_call` (G5). Every event passes the redactor's
`stream` profile before any subscriber sees it.

### 5.5 Usage and cost (INFRA-20)

One row per request in `session$usage`:

```
request_id  session_id  agent  parent_id  provider  model  route  input  output
cache_read  cache_write_5m  cache_write_1h  reasoning  images  cost  tier
stop_reason  started  seconds  estimated
```

`route` is one of `api`, `plan-cli`, `siwc`, `system-one`, `emulated`. `estimated` is TRUE when the
provider reported nothing (aborted before usage) and the calibrated estimator filled the row.
System 1 calls outside any session append to a process accounting log (append-only list, not run
state) so `gptr_usage()` can include them; the same record sits in the vector's `meta$usage`.
Cost comes from `catalog-prices.R` (1 h cache writes at 2x input, 5 min at 1.25x, reads 0.1x or
the model's own rate, 07 §summary). CLI plan runs report `total_cost_usd` as an estimate.

### 5.6 System 1 typed vectors (04 §4.5)

| Class | Base type | Attributes |
|---|---|---|
| `c("gptr_decision", "gptr_s1", "logical")` | logical | `names`, `prob` (P(yes)), `threshold`, `meta` |
| `c("gptr_choice", "gptr_s1", "character")` | character | `names`, `s1_levels` (options in request order; never `levels`), `probabilities` (matrix, rows = states), `confidence`, `meta` |
| `c("gptr_score", "gptr_s1", "numeric")` | double (expected 0-based level) | `names`, `s1_levels`, `probabilities`, `confidence`, `meta` |

`meta = list(model = "jev-1.13.0" (physical), alias = "jev-latest", engine = "typesafe" |
"emulated:structured" | "emulated:logprobs", calibrated, question, date, cached (lgl per element),
errors, usage)`. Methods: `[`, `[[`, `[<-` (degrades to the bare vector for foreign values),
`c`, `rep`, `format` (`TRUE (p=0.93)`), `print`, `as.data.frame`, `as.logical`/`as.character`/
`as.double` (bare), `Ops`/`Math`/`Summary` group methods that return bare vectors (so
`cell_type == "unclear"` is a plain logical), delayed vctrs methods (Suggests).

### 5.7 Artifacts (17 §4)

```
.gptr/artifacts/<id>/app.R                 editable source (the model edits it with `edit`)
.gptr/artifacts/<id>/artifact.json         {id, title, kind, versions, current, data, created}
.gptr/artifacts/<id>/v001/{app.R, R/gptr_data.R, data/<name>.rds}   immutable snapshot per launch
.gptr/artifacts/<id>/run/{run.json, port, app-v001.log}              runtime, gitignored
```

`gptr_artifact` (list): `id`, `title`, `kind` (`"shiny"`, `"html"`), `version`, `dir`, `url`,
`port`, `pid`, `data` (names, bytes, snapshot time), `checks` (`parse`, `launch`, `http`, `session`
with messages), `screenshot` (PNG path), `status`. Without a workspace the root is `tempdir()`.

### 5.8 Workspace snapshot (12 §3.8, 21 §2.9)

`env_snapshot(envir)` -> data frame `name, kind (value|promise|active), address, class, bytes,
shape, fp`; `fp` = type + length + attribute and column addresses + 64 sampled values (never
expanding compact row names). Changes = address change, fingerprint change, or an assignment
target found by static analysis of the evaluated code (replacement functions, `assign()`, `:=`,
`set*()`, `<<-`). A full `rlang::hash()` pass is off by default (ALTREP gives false "modified",
12 verifier) and available under `.opts$hash_budget`.

### 5.9 Sub-agent handles

A child is a `gptr_session` with `kind = "child"` plus `backend` (`"inline"`, `"worker"`,
`"cli"`), `agent` (definition name), `exports` (names written back), and for out-of-process
backends a `proc` list (`process` handle, `spec_path`, `result_path`, `events_seen`). Inline
children evaluate in `new.env(parent = envir)` (overlay; 15 §4.5). A team session's `$` and `[[`
return children by name; `gptr_usage(team)` sums children.

### 5.10 Settings

Layers, lowest to highest: package defaults < user `R_user_dir("gptr","config")/settings.json` <
project `.gptr/settings.json` (trusted projects; may only tighten `mode`, `permissions`, `context`)
< `.gptr/settings.local.json` < `options(gptr.*)` < `gptr_config(.scope = "session")` < call
arguments. Keys: `model`, `small_model` (compaction, emulation, cheap sub-agents), `mode`,
`permissions{allow, ask, deny}`, `tools{preset, enable, disable}`, `context`, `record`, `replay`,
`transcript`, `commit_cache`, `plugins`, `filters`, `skills{paths, budget}`, `mcp{exposure}`,
`subagents{depth, max_active, max_workers}`, `output_tokens`, `plot{width, height, res}`,
`budget{tokens, cost}`, `cache{ttl}`, `system1{model, emulate}`, `providers{<id>: {...}}`,
`egress{<provider>: "ack"}` (user scope only).

---

## 6. Key internal interfaces

### 6.1 Provider adapter contract (INFRA-17, G1 row 2)

```r
gptr_adapter(api = "anthropic-messages", transport = "http_sse",
  build = function(model, context, options) {
    # context = list(system = list(t0 =, t1 =), messages = <projected, transformed>,
    #                tools_json = <frozen>, tool_choice =, cache = <breakpoint plan>)
    # returns list(url =, headers = <list of values or gptr_secret handles>, body = <json string>)
  },
  parse = function(model, options) {
    # returns a normaliser: list(push = function(event_text), finish = function(),
    #   fail = function(condition), message = function()) that emits INFRA-02 events through
    #   options$emit; never throws after `start`; accumulates linearly (closure buffers)
  })
```

Transports: `http_sse`, `http_ndjson`, `http_json` (System 1), `process_jsonl` (CLI providers:
`build` returns `list(command, args, stdin, env, control = <handler>)`), `inprocess` (fake
provider, emulation). A provider record binds `api` to an adapter and carries `base_url`,
`auth` (zero-argument resolver returning a `gptr_secret` handle), `compat`, catalog entries.
`headers` holding handles are materialised only inside `http-request.R` and only for the
provider's configured origin (G6 origin binding).

### 6.2 Reactor (D-13; 15 §4.2)

```r
reactor_get()                                   # the process reactor (pool, fds, timers, FIFO)
reactor_http(spec, on_bytes, on_done, run)      # -> transfer id; pipewait = 0L; timeouts
reactor_proc(proc, on_line, on_exit, run)       # watch a processx child's stdout/stderr
reactor_timer(at, fn)                           # retries, backoff, idle checks
reactor_enqueue_tool(run, call)                 # FIFO: one R-evaluating tool at a time
reactor_pump(until = function() FALSE, slice_ms = 100, allow_runs = NULL)
reactor_cancel(ids)                             # multi_cancel, interrupt, grace, kill_tree
```

One iteration: `processx::poll(c(curl_fds(multi_fdset(pool)), <pipes>), slice)`;
`curl::multi_run(timeout = 0)`; read ready pipes (at most 512 chunks each, 16 §4); fire due
timers; if `later` is loaded, `later::run_now(0)` (services httpuv servers such as
`gptr_mcp_serve()` and OAuth callbacks; never `httpuv::service()`, 16); run at most one queued R
tool, then loop. `allow_runs` restricts which runs may execute tools during a nested pump (a
sub-agent started from inside an `r` evaluation). Admission control: global and per-provider
semaphores fed by the rate limiter (INFRA-21). The reactor is the only blocking wait in gptr.

### 6.3 Agent loop (INFRA-12; 02 §4.1)

```r
run = agent_run_new(session, prompts)           # state machine environment
agent_step(run)   # -> "request" | "tools" | "done"; drives one turn through the reactor
agent_loop(session, prompts)                    # agent_step() until settled; interrupt policy
```

Hooks read from the registry at each turn: `context` (transform chain), `before_provider_request`
(read-only in the default build: must not change the frozen prefix; a `cache_break` event names a
handler that does), `tool_call`/`permission_request` (fail closed), `tool_result` (patch chain),
`turn_end`. Steering is polled at loop start, after `turn_end` and after tool preflight; delivered
after the complete tool-result message. `max_turns` 50 programmatic, 200 in the REPL.

### 6.4 Tool dispatcher (INFRA-09/10)

```r
tool_dispatch(calls, run) # -> list of gptr_tool_result, in source order; never throws
```

Per call: look up the tool (unknown -> error result), validate and coerce arguments against the
schema (missing required -> error result, never `NA`), `perm_check()`, then execute: sequential
tools through the reactor FIFO, concurrent ones as reactor work. A `length`/`refusal` stop fails
every call of that turn unrun. Interrupt during a tool -> "interrupted after 2.3 s; side effects may
have occurred" (INFRA-04). One sequential call makes the batch sequential (Pi).

### 6.5 Evaluator (12 §4.3)

```r
eval_r(code, envir, timeout = NULL, plots = "auto", tee = interactive(), budget_tokens = 2000L,
       guard = TRUE, rng = NULL, overlay = NULL, record = TRUE)
# -> gptr_eval_result: status, events, n_done, n_total, changes, elapsed, plots, assigned
format(x, budget_tokens)  # model text: output, messages, warnings, error + trimmed traceback,
                          # "[plot N attached as image]", state-change lines, status line,
                          # truncation notice with a gptr$out(id) handle
```

`timeout = NULL` means none when a human is present (Ctrl-C menu) and `getOption("gptr.r_timeout",
3600)` otherwise; per expression via `setTimeLimit(transient = TRUE)`, best effort (12 §A6).
Symbols print via `print(<sym>)` in `envir`; assignments, loops and `invisible()` never pass through
`withVisible()` (sticky references, 12 §C2). Plots: drawn on the user's device when one is open or a
human is present, recorded and replayed to PNG at 768x512, res 96 (~532 Anthropic tokens, 12 §3.5).
`rng` swaps in a per-agent L'Ecuyer stream (15 §5.12) so inline sub-agents never touch the user's
`.Random.seed`.

### 6.6 Environment snapshot and diff

```r
env_snapshot(envir, sizes = <address-keyed cache>)  # -> data.frame
env_diff(old, new, assigned = character())  # -> list(added, removed, modified)
env_summary(envir, budget = 600L, snapshot)  # -> character # one line per object, largest first
gptr_describe(x, budget = 300L)                            # S3; leaf discipline
```

### 6.7 Permission hook (INFRA-11; 18 §4.7)

```r
perm_check(call, run)
# -> list(decision = "allow" | "deny" | "ask" | "modify", reason, input,
#         risk = list(level, categories, flagged))
```

Order: every `policy` record (deny > ask > modify > allow; a throwing policy denies), then
`permission_request` hooks (first decision; a plugin such as a System 1 reviewer may answer an ask),
then the UI (`gptr_ui` backend). `ask` without a UI is a deny whose text says the action was not
performed and how to allow it. Built-in policies: `mode` (table in §9.3), `rules` (18 §3.7
grammar), `critical_guard` (level 4 asks even in auto), `secret_guard` (G6), `protect_size`
(overwriting an object above `gptr.protect_size`, default 100 MB, is level 3), `undo` (snapshots
by `mget()` only for objects whose total size stays under `gptr.undo_max_bytes`, default 1 GB, and
dropped at the next turn boundary, because a held snapshot makes the next in-place edit copy the
object; critic `undo_copy.R`).

### 6.8 Document writer (14 §4)

```r
doc_locate(call, prompt, calls = sys.calls(), frames = sys.frames())  # -> doc_site
doc_decide(site, prompt_hash, mode)  # -> "replay" | "run" | "regenerate" | "error"
doc_upsert(site, block)  # -> list(action, block_id, lines, backend)
doc_block(session, turn)  # -> list(header, code, outputs, notes, artifacts)
```

Writers are `doc_format` specs (`r`, `rmd`, `qmd`, `ipynb`, `transcript`); every write passes
`document_write` (fail closed, patchable), then atomic I/O with an md5 conflict check. Under
`Rscript` writes are deferred to a `reg.finalizer(onexit = TRUE)` with a pending sidecar file.

### 6.9 Session store (INFRA-13)

```r
store_open(session, dir)          # dir = .gptr/sessions when a workspace exists, else tempdir()
store_append(store, entry)        # suspendInterrupts(); writeLines(useBytes = TRUE); flush
store_read(path)  # -> entries # tolerant to a torn last line
store_fork(path, leaf_id, new_path)
store_resume(id, envir)  # -> gptr_session
```

### 6.10 MCP client (D-14; 16 §4)

```r
mcp_connect(spec)  # -> mcp_conn # stdio (processx) or HTTP (reactor); era probe cached per config
mcp_tools(conn)  # -> list of tool specs (exposure from config; default "r")
mcp_call(conn, tool, args, timeout, on_progress)  # -> gptr_tool_result # MRTR <= 5 rounds
mcp_close(conn)
```

### 6.11 Sub-agent backends (D-12)

```text
gptr_backend("inline", start = function(spec, parent) <child session registered on the reactor>,
             poll = NULL, cancel = function(child) gptr_cancel(child))
gptr_backend("worker", start = <spawn Rscript inst/scripts/worker.R spec.rds via processx>,
             poll = <read JSONL events from the child's stdout>, cancel = <interrupt, 5 s, kill_tree>)
gptr_backend("cli", start = <spawn claude/codex via the cli-* adapter>, ...)
```

The worker child is ordinary gptr: `worker.R` reads the spec (prompt, model, mode, shipped objects
by name, depth), runs `gptr()` with the JSONL front end on stdout and the `rpc` UI backend on stdin,
and saves the designated value to `result_path` (no callr; §8).

### 6.12 CLI providers (INFRA-19)

`cli-claude`: one long-lived child per session: `claude -p --input-format stream-json
--output-format stream-json --verbose --include-partial-messages --tools "" --strict-mcp-config
--setting-sources "" --disable-slash-commands --mcp-config <file> --permission-prompt-tool stdio
--system-prompt-file <file> --model <full id>`; never `--bare` (07 §design). gptr's R tools are an
in-process `sdk` MCP server answered over the control protocol (`mcp_message`), permission prompts
arrive as `can_use_tool` and go through `perm_check()`; Ctrl-C sends `control_request interrupt`.
Stream events reuse the Anthropic normaliser (`push_parsed`). `cli-codex`: `codex exec --json
--ignore-user-config -c mcp_servers.gptr.url=... -c mcp_servers.gptr.bearer_token_env_var=...
-c mcp_servers.gptr.tool_timeout_sec=3600 -` with the prompt on stdin (08 §design, 16); R tools
come from `gptr_mcp_serve()` running inside the session and serviced by the reactor pump. Both:
UTF-8 pipes, `write_all()` (08 verifier: `write_input` truncates silently above 8 KB), refuse
`.cmd`/`.bat` shims on Windows, secrets and billing-switch variables removed from the child
environment (G6).

### 6.13 INFRA-01..28 compliance

| INFRA | Met by | Acceptance test (file) |
|---|---|---|
| 01 curl multi transport | `http-reactor.R`, `http-request.R` (`pipewait = 0L`) | first delta within 0.35 s; 6 streams within 10% of slowest (`test-http-reactor.R`) |
| 02 normalised events | `provider-events.R`, every adapter | golden sequences; truncated stream -> one `error` with partial (`test-provider-*.R`) |
| 03 interrupt resume/steer/abort | `console-interrupt.R`, `reactor_cancel()` | scripted SIGINT at TTFT/body/tool (`test-console-interrupt.R`, skip_on_cran) |
| 04 honest partials, projection | `provider-transform.R`, `tool-contract.R` | 401 recorded, not replayed; aborted tool gets truthful result |
| 05 layered timeouts | `http-request.R` (connect, first byte, idle; no total) | mock holds headers; 10-min slow stream completes |
| 06 bounded retry | `http-retry.R`; S1 rounds in `s1-client.R` | `retry-after: 2` retried; `3600` fails fast with the delay; spend-cap 429 never retried |
| 07 message model | `provider-message.R` | byte-identical re-serialisation of thinking/encrypted/thought-signature fixtures |
| 08 hand-off | `transform_for()` in `provider-transform.R` | Anthropic -> Responses -> Gemini bodies contain no foreign opaque fields |
| 09 validation | `json-schema.R`, `json-partial.R` | `{"n":3}` without `code` -> error result, function not called |
| 10 never-throw dispatcher | `tool-contract.R` | throw/interrupt/warn-as-error/timeout property test |
| 11 permission hooks | `perm-gate.R` | 18's mode x risk matrix; `modify` visible in transcript |
| 12 loop with queues | `agent-loop.R` | 02's 24 checks; steering after tool results on the wire; `max_turns` |
| 13 append-only store | `session-store.R` | SIGKILL mid-stream then resume; `.Random.seed` unchanged over 1,000 appends |
| 14 session semantics | `session-object.R`, `gptr_fork()` | fork never shares listeners; different leaves |
| 15 no global run state | design rule; weak live-session index | two concurrent sessions, separate usage |
| 16 one reactor | `http-reactor.R`, `subagent-backends.R` | 15's `p10_mixed` shape: inline + worker + CLI interleave; tools never overlap |
| 17 data + few adapters | `provider-registry.R`, `gptr_provider()` | Ollama added by data; fake provider passes conformance |
| 18 System 1 type | `s1-*.R` | `if (gptr(..., model = jev))` on mocked `/systemone`; 100 items capped by `max_active` |
| 19 subscription CLIs | `cli-*.R` | fake-CLI fixtures stream concurrently; abort leaves no process tree |
| 20 usage by route | `session-usage.R`, `catalog-prices.R` | 1 h cache-write fixture gives the documented dollar amount |
| 21 rate limits | `http-retry.R` limiter feeding admission | 20-agent fan-out never exceeds advertised budget |
| 22 credentials | `auth-*.R` (vault, handles, redactor) | grep of JSONL, wire log and `format(request)`: zero key bytes (G6 e2e) |
| 23 byte-level decoding | `http-sse.R` | 20,000 deltas < 1 s CPU; random re-chunking identical |
| 24 testability | `provider-fake.R`, helpers, fixtures, `gptr_check()` | whole INFRA suite offline under `--as-cran` in < 60 s |
| 25 structured output with tools | adapters' `output_schema` option; S1 emulation | typed value plus tool calls in one transcript |
| 26 loop-owned context | `prompt-context.R`, `agent-recovery.R`, `prompt-compact.R` | overflow -> one compaction + retry; entry appended |
| 27 rendering decoupled | `console-render.R` subscribes to events | byte-identical transcripts at verbosity 0/1/2 |
| 28 observability | opt-in wire log (redacted JSONL); `otel` in Suggests | one line per request and terminal event, no secrets |

---

## 7. Positions

### 7.1 Open decisions D-01..D-28

| ID | Position | Rationale and evidence |
|---|---|---|
| D-01 | Settled by S-10. The own layer sits on **curl** (streams, reactor) and **openssl** (PKCE randomness, hashing, base64); **no httr2**. | Every stream must go through the curl-multi reactor (10a INFRA-01; E1/E2, V-7/V-8: httr2 connections block on headers and batch at 64 KiB). httr2's remaining uses (OAuth helpers, mocks) are small: `oauth_flow_auth_code_read` is internal anyway (16 verifier), its mocks do not cover our reactor, and PKCE/token POSTs were prototyped with curl+openssl (03 §5). Dropping it removes 7 packages from the dependency closure (httr2, glue, lifecycle, magrittr, rappdirs, vctrs, withr; P-C `deps.R`, §8). |
| D-02 | S3 classes; mutable objects are environments (session, registry, ctx, reactor, jobs); immutable values are classed lists and base-typed vectors. No R6/S7 in the public contract. | G1 §4.3 measurements; 10a §16 warns against R6/S7 on hot paths; 04: S1 values must be base-typed for `if()`. Report 02's R6 `Agent`/`SessionStore` become the session environment plus functions. |
| D-03 | Model-visible default: `r`, `read`, `edit`, `write` (+ `ask` only when a human is present). `grep`, `find`, `ls` are `gptr$grep()` etc. inside `r` (opt-in as tools in the `extended` preset). No `agent`, `artifact` or `shell` tool by default: sub-agents are `gptr()` calls, apps are `write` + `gptr$app()`, programs are `gptr$sh()`. | Claude Code turned Glob/Grep off by default on Unix (20 §summary): frontier models search through the execution tool. Saves 513 schema tokens per request against the 7-tool set (G4 §2.8: grep 235, find 180, ls 98) and 352 for `artifact`. Every tool beyond the four is justified: `ask` needs a UI pause that R code cannot express safely inside a run (18 §3.6). |
| D-04 | `envir = parent.frame()`, explicit override; inline sub-agents `new.env(parent = envir)`; magrittr mask fix (12 §B4). | 12 §B verified parent.frame semantics and R CMD check behaviour; 15 §4.5 overlay policy. |
| D-05 | `gptr()` returns the session environment (S-8). Printing shows the latest answer; `$text`, `$value` (by name), `$usage`, `$history`. Running sessions take piped prompts as steering, idle ones as follow-ups (same queue as Ctrl-C and `gptr_steer()`). Fork = `gptr_fork(s)`, recorded as an ordinary statement whose block header carries `fork=<id>`. Data-first pipe is told apart by the class of the first argument. System 1 calls return typed vectors, ending a pipe. | S-8; INFRA-14; G1 §4.6 (one queue); P-C `byname.R` (value by name). |
| D-06 | `gptr(q, x, model = jev, choices =, levels =, threshold = 0.5, uncertain =)`; returns `gptr_decision` / `gptr_choice` (**classed character**, `output = "factor"` optional) / `gptr_score`; vectorised on the reactor; abstention off by default, `.opts$min_confidence` + `uncertain` (NA, TRUE/FALSE, "stop", function). Emulation: gateways first, then an interactive one-time offer; never silent. | 04 §4.5 (factor truthy in `if()`, `switch()` warns); 04 §4.6; S-1 forbids decide()/classify() exports (10 Q4 collisions). |
| D-07 | rlang `enquo()`/`enquos()` capture; alias wins over same-named variables; `!!` escape; one-time notice when a character variable is shadowed. | 12 §2.D1-D2 (forwarded-dots bug in base `substitute()`; copy safety); 10 Q4 (attached packages export alias names). Overturns D-07's base-only preliminary with that reason. |
| D-08 | 14's block grammar below the originating top-level call; `#>` outputs (12 lines max); `## Decision:`; replay modes auto/replay/live/record; non-interactive runs replay when a fresh block exists; **cassettes** for nested calls (§4.1.7). | 14 §3.1, §4.4; NS-11 needs nested replay. |
| D-09 | Machine form: Pi v3 JSONL tree with gptr custom entries under `.gptr/sessions/` (tempdir without a workspace). Human form: the document. | 02 §2.11; INFRA-13; 10 verifier: corteza has only flat v2, so a v3 tree is a real differentiator. |
| D-10 | `.gptr/` only via `gptr_init()` (interactive confirmation when `path = NULL`) or an interactive yes; global state in `R_user_dir("gptr", ...)`, small and pruned (`gptr_cache("prune")`). | 13 §2 and C-items; 17 verifier (CRAN "actively managed" proviso). |
| D-11 | Modes `plan`, `manual`, `edits`, `auto` (§9.3); advisory classifier; deny > ask > allow > mode; project settings only tighten; asks fail closed. Default: `manual`. | 18 §4.7; NS-12. |
| D-12 | Backends `inline` (default), `worker` (processx `Rscript` running gptr with a JSONL front end), `cli` (claude, codex). `backend = "auto"` everywhere: inline unless the model is CLI-only. `fork` deferred. | 15 §4.4 (inline zero-copy, 5 agents 5.2 s vs 14.0 s sequential); 15 verifier flagged the auto/inline inconsistency, resolved here to "auto" in `gptr_agent()`, `gptr_map()` and teams. Fork is Unix-only and unsafe in GUIs (15 §2.8). |
| D-13 | gptr-owned reactor on curl multi handles, `processx::poll()` over `curl_fds()` plus child pipes, one per process; `later` only for idle servicing (background runs, httpuv servers). | 15 §4.1 (measured), 10a INFRA-01/16. |
| D-14 | Own MCP client speaking 2025-11-25 and 2026-07-28 (probe, cached era); default exposure `r` (`gptr$mcp$server$tool()`), per-tool `direct`/`deferred`/`hidden`; gptr as a server: Claude `sdk` transport, httpuv HTTP for Codex and external clients. | 16 §4 (both eras; 27-tool interop with `claude mcp serve`); G1 §2.5 (36 vs 328 tokens per tool). |
| D-15 | Drive the unmodified `claude` and `codex` CLIs through processx; ChatGPT plan also natively through Sign in with ChatGPT (opt-in `gptr_login("chatgpt")`). Claude plan provider opt-in with a one-time notice; never read CLI credentials. | 03 §ToS, 07 §policy (legal status UNCERTAIN; maintainer to ask Anthropic), 08 §SIWC. |
| D-16 | Agent Skills folders; extensions are `function(gptr)` factories (file last expression or exported package function named in `inst/gptr/plugin.json`); plugins are directories or packages with `inst/gptr/`; declarative resources auto-available from attached packages, code only when enabled. | 05 §4.10, 16 §4.9, G1 §4.4. |
| D-17 | Shiny app in a background `Rscript` child (generated `run.R`, parent-PID watchdog, port file), data snapshot per version, registry under `.gptr/artifacts/`; driven by `gptr$app()` from `r`. | 17 §4 (callr replaced by a generated script so the artifact directory is self-contained and runnable with `Rscript run.R`). |
| D-18 | `provider/id[:thinking]` plus dynamic aliases; pruned models.dev snapshot in `inst/extdata`; refresh only on request; canonical ids written to documents. | 09 §4. |
| D-19 | Provider-reported usage plus a calibrated estimator (chars/4 prose and code, chars/2 tool output, 1 per CJK char); G4 trigger formula; in-conversation checkpoint; no in-place micro-compaction; tool output bounded at entry. | 21 §2.8; G4 §4.4, §2.10. |
| D-20 | Imports: cli, curl, jsonlite, openssl, processx, rlang, yaml (7). | §8. |
| D-21 | No compiled code in v1; 21's Rcpp procedure kept for the watch list (SSE splitting, grep on huge trees). | 21 §summary and verifier (no verdict changed). |
| D-22 | Vault + handles; one redactor at every sink, ingress-only; `.env` loader with aliases; origin-bound credentials; secret guard in the classifier. | G6. |
| D-23 | `Depends: R (>= 4.2.0)`. | 13 (UTF-8 on Windows, `_` placeholder), 12, 16. |
| D-24 | Fake provider, base-R mock SSE server (processx child, skip_on_cran), wire fixtures, adapter conformance via `gptr_check()`, tracemem suite, prefix-stability test, token benchmark in `dev/bench`. | 10a INFRA-24; 13 §5; G4 §4.9. |
| D-25 | Pi-derived canonical event names plus nine gptr events; Claude/Codex names accepted only when importing `hooks.json`; `tool_call`, `permission_request`, `document_write` fail closed. | G1 §3.2. |
| D-26 | cli-rendered console; interrupt returns to the prompt; `!`/`!!` run R; slash commands; compact one-line permission prompt. | 18 §4.3-4.6. |
| D-27 | `gptr()` in R chunks is the interface; `knit_print` methods; the `{gptr}` engine ships as `builtin:knitr-engine`, **disabled by default** pending the maintainer (it relaxes S-2 for prose). Under R CMD check and vignette builds replay is forced. | 14 §4.6, 13 open question. |
| D-28 | `gptr()` plus 72 `gptr_*` exports; the dispatcher is the gateway namespace `gptr$...`, not an exported `tools` or `gptr_tools` object. | G1 §4.7 collisions; G5 (the classed gateway passed R CMD check codoc); fewer exports and one name to learn. |

### 7.2 Cross-track conflicts (critic list, C-1..C-33)

The known list maps onto the critic list: K1=C-1, K2=C-2, K3=C-3, K4=C-4, K5=C-5, K6=C-6, K7=C-7,
K8=C-8, K9=C-9, K10=C-10, K11=C-11, K12=C-12, K13=C-13, K14=C-14, K15=C-15, K16=C-16, K17=C-17,
K18=C-18.

| # | Conflict | Resolution |
|---|---|---|
| C-1 | R6 vs S3 + environments | S3 + environments (D-02). R6 arrives transitively through processx; gptr never uses it. |
| C-2 | Transport and SSE parsing | curl-multi reactor for every HTTP request including System 1 and MCP HTTP; own vectorised byte-level SSE/NDJSON splitter (21 §2.6: 23-29 µs/event vs 288-462 µs for `resp_stream_sse`; 08 verifier: `resp_stream_sse` drops an unterminated final event). No httr2, so its minimum-version disagreement disappears. |
| C-3 | Imports budget | 7 Imports (§8): cli, curl, jsonlite, openssl, processx, rlang, yaml. callr, httr2, ps (as a direct dependency), R6 out. `later`/`httpuv` in Suggests: the reactor works without them; `gptr_mcp_serve()`, the OAuth loopback and `background = TRUE` check for them with `rlang::check_installed()`. yaml in Imports because skills are core and a hand parser lost skills with folded scalars (05 §summary). |
| C-4 | NSE capture and ambiguity | rlang capture (12 D2); alias wins, `!!` escape (12 D1, 10). 09's and 05's "bound variable wins" rules are rejected because an attached package exporting `codex` or `gemini` would silently hijack `model = codex`. |
| C-5 | Evaluator; plot size | Hand-rolled evaluator (12 §A2: evaluate's sink, device and sticky-reference defects). Plots for the model at 768x512 res 96 (~532 tokens, 12 §3.5); artifact screenshots at 1000x700 (~900 tokens, 17) because page layouts need width. 17's "capture via evaluate()" is replaced by 12's recorded-device capture. |
| C-6 | Tool surface; R tool name; todo; edit result | Four tools (D-03), tool named `r` (D-03, 12, 14, G4: 1 token, matches `gptr$` idiom). No todo tool (20: off by default in Claude Code and Codex). `edit` returns Pi's message; the diff is appended **only** when fuzzy matching, EOL or encoding normalisation changed something the model did not literally ask for (saves up to ~1,000 tokens per edit against a 4 KB diff; the user and the document still get the full diff from `details`). `edit` accepts a pasted `*** Begin Patch` envelope (20 §4.3), so GPT-family habits cost no extra schema; a dedicated `apply_patch` tool is a built-in plugin, off in v1, re-evaluated by the benchmark (§14.5). |
| C-7 | Dispatcher name | `gptr$<member>`; MCP under `gptr$mcp$<server>$<tool>()`; no `tools` (base package name) and no `mcp` object (collisions). |
| C-8 | Default sub-agent backend and limits | `auto` = inline except CLI-only models (D-12). Limits: 8 inline concurrent, 4 CLI, workers `min(4, cores - 1)` and at most 2 when `_R_CHECK_LIMIT_CORES_` is set (15 §3.7; the verifier's omit=1 edge noted); depth 2 by default (nested `gptr()` inside a child's `r` is allowed once; Claude uses 3, 15 proposed 1, 20 two). 50 KB returned per child. Naming: "worker" (D-12). |
| C-9 | System 1 API | Classed character choices; single gateway; `uncertain` + `.opts$min_confidence` (D-06); requests on the reactor with bounded rounds (not `req_perform_parallel`). |
| C-10 | Return value | The session object (S-8). 12's `gptr_result` fields become session accessors; 15's `gptr_results` becomes a team session. |
| C-11 | Claude plan bridge | CLI stream-json with the control protocol and the in-process `sdk` MCP server as primary; the HTTP fallback configured with `tool_timeout > 60 s` (07 verifier: 60 s per-request timer). Opt-in with notice; provider id `cli-claude`, user alias `claude_code` (names the program the user runs; UNCERTAIN under the name-use rule, flagged for the maintainer). |
| C-12 | ChatGPT plan route | `model = codex` -> `cli-codex` via `codex exec --json` + in-session HTTP MCP (documented, stable). Native `openai` provider with `auth = "chatgpt"` (Sign in with ChatGPT preview) is opt-in and recommended in docs because it avoids Codex's 19-38K tokens per turn (08). app-server deferred (experimental, schema drift, 08 risks). |
| C-13 | MCP eras | Client speaks both (16 §4 algorithm); era cached per server config to pay the 5 s probe once. |
| C-14 | Append-only vs compaction | Strictly append-only; compaction is an appended checkpoint entry; projection instead of edits; no in-place micro-compaction (G4 §2.10: +32% cost, 25 invalidated thinking blocks). |
| C-15 | Workspace consent and locations | `gptr_init(path = NULL)`: interactive proposal + yes/no, non-interactive error (13 + NS-9). Without `.gptr/`: sessions, artifacts and caches in `tempdir()`; S1 cache in memory. |
| C-16 | Steering channels | One queue per session. Producers: pipe into a running session, Ctrl-C menu (steer / follow-up), `gptr_steer()`, a sibling agent's code, optional file inbox plugin. Consumer: the loop after each complete tool-result message (INFRA-12). |
| C-17 | Script-as-history under Rscript and source() | Deferred writes at exit; content matching; live regeneration only via `gptr_source()`, knitr or IDE line-by-line; `base::source()`/Rscript downgrade `live` and stale regeneration to replay with a warning (14 §4.4.2). NS-7's `options(gptr.replay = "live")` therefore means "under `gptr_source()` or the IDE". Reading `source()` frame locals is wrapped in `tryCatch` and falls back to content matching (14 verifier: CRAN grey zone). |
| C-18 | Copy safety vs snapshots, guards, hashing | Designated values by name (P-C); `/undo` only under a byte budget and dropped at the next turn; binding-lock guard applied to inline *sub-agents* only and measured for refcount effects in the tracemem suite (15 did not check; plan P18 adds the case to P08's suite); artifact snapshots via a leaf `saveRDS()` wrapper; hashing by address + sampled fingerprint + static assignment targets, full hash only under an explicit budget (21 §2.9; 12 verifier on ALTREP). |
| C-19 | S1 decisions in the history document | Not written into documents (14 §4.4.8); cached per element (input hash only) and emitted as `decision` events into the session JSONL. REQ-26(c) is met by the *user's* control-flow code, which is already in the document. |
| C-20 | Project instructions placement | G4: first user message, cache-anchored; AGENTS.md then CLAUDE.md root to cwd, `.gptr/vignette.Rmd` last and additive (14 §4.8); precedence stated once in the static `<context>` section; system prompt frozen. |
| C-21 | Hook taxonomy | Pi-derived names + nine gptr events (G1 §3.2, D-25). |
| C-22 | Mode names and plan mode | plan/manual/edits/auto. Plan: level <= 1 R in a scratch child env, denials for writes, final `<proposed_plan>` saved to `.gptr/plans/` and kept as the session's pending plan (§9.4). Without a UI: `ask` -> deny. |
| C-23 | Compaction thresholds and estimation | G4 trigger `min(window - min(max(30k, 0.10 window), 0.25 window), 200k)` plus the cold-cache rule; estimator chars/4 prose, chars/2 tool output (21 §2.8: chars/4 underestimates printed R by 51%). Pi's 16,384 reserve is superseded. |
| C-24 | Skill catalog | Budget `max(8000 chars, 1% of window)`, least-recently-used descriptions dropped first (16, G1); activation through `read` (no skill tool: a tool with a name enum changes whenever skills change and breaks the cached tool array); `skills =` preloads bodies as `<skill_content>` in the first user message. |
| C-25 | Bash mapping in foreign agent files | Bash/PowerShell -> `r` (15, 16, G5; S-4). |
| C-26 | Opt-in shell tool vs S-4 | No built-in shell tool. G5's `gptr$sh()` covers it; a `shell` adapter may exist only as a third-party plugin routed through the `r` pipeline (G5 §8). |
| C-27 | Exported names | 73 names, all `gptr` or `gptr_*` (§4). Unprefixed proposals (decide, classify, artifact, mcp_tools, tools, agent) are internal, namespace members or mask aliases. |
| C-28 | knitr chunk engine | Opt-in plugin, off (D-27); replay forced when `_R_CHECK_PACKAGE_NAME_` is set or `GPTR_REPLAY=replay`. |
| C-29 | File-tool recipes | grep: `readBin` per file, `grepRaw(fixed = TRUE)` prefilter for literals, whole-file `(?m)` PCRE prefilter for regex, NUL sniff, early stop, never per-file `readLines` (21 §2.1 beats 19's recipe; 11's readChar batching kept for many small files). read: raw newline index up to 16 MiB, streaming chunked index above, cached sparse index (path, size, mtime) above 20 MB (11 + 21). diff: patience anchors + Myers capped at D = 256, no diffobj (21 §2.3). find: Pi's `**/` prefix for patterns containing `/` (11 verifier: models expect Pi semantics). |
| C-30 | One event loop for reactor, later, httpuv | The reactor's iteration calls `later::run_now(0)` when later is loaded (§6.2); outside runs, later's own loop services httpuv and background runs. On Windows `later_fd` cannot watch processx pipes (15 verifier: LIKELY), so background runs poll with a timer instead of fd callbacks. |
| C-31 | S2 cache committed vs privacy | S2 answers and cassettes gitignored by default; `gptr_init(commit_cache = TRUE)` opts in (Quarto `_freeze` analogy); S1 cache committed (it stores input hashes only, 14 §3.5); all cached text redacted at ingress (G6). |
| C-32 | Default models | Default chat model by first available route: Anthropic key -> `anthropic/claude-sonnet-5-5` (NS banner; $2/$10 vs $4/$20 for Opus 5.5, 07); OpenAI -> `openai/gpt-6-sol`; Gemini -> `google/gemini-3.8-flash` (09); else a detected CLI. Aliases resolve to full ids; CLI invocations always pass full ids (07: CLI aliases lag). |
| C-33 | Retry constants | Transport: retry 408/409/429/5xx/529 and network errors before the first committed delta, `0.5 s * 2^i` with time-derived jitter (no RNG), cap 8 s, at most 4 attempts; honour `retry-after-ms`/`retry-after` up to `max_retry_delay = 60 s`, fail fast beyond with the server's value (10a INFRA-06); never retry the spend-cap 429 (07). Agent level: 2 retries on classified transient errors (02). System 1: bounded rounds resubmitting failed elements only, 3 rounds (04 §4.7). |

---

## 8. Dependencies

`Depends: R (>= 4.2.0)`. `NeedsCompilation: no`. No R LLM package anywhere (S-10).

### 8.1 Imports (7; closure 11 packages)

Verified with `tools::package_dependencies()` on the installed library (P-C `deps.R`): the closure
is cli, curl, jsonlite, openssl, processx, rlang, yaml plus ps, R6 (via processx) and askpass, sys
(via openssl): **11 packages**. The alternative with httr2 and callr has 19 (adds callr, glue, httr2,
lifecycle, magrittr, rappdirs, vctrs, withr).

| Package | Why it is required | Used by |
|---|---|---|
| curl (>= 7.0.0) | versions exercised by 15 and 10a (the 02 verifier re-ran on 8.0.0); the reactor: multi handles, `multi_fdset()`, push callbacks, `pipewait = 0L`, `multi_cancel()`; one transport for streams, System 1, MCP HTTP, OAuth and catalog refresh (15 §4.1, 10a INFRA-01) | `http-*`, `auth-oauth`, `mcp-client`, `s1-client` |
| jsonlite | every wire format, JSONL store, settings (conventions §6) | everywhere |
| processx (>= 3.8.0) | `poll()` over curl fds and pipes, children for workers, CLI providers, MCP stdio, bridges, artifacts; `kill_tree()` (15, 16, 17, G5) | `proc-*`, `http-reactor`, `cli-*`, `mcp-*`, `bridge-*`, `artifact-*` |
| cli | console rendering and capability detection (18), `hash_sha256()` | `console-*`, `utils-hash` |
| rlang (>= 1.1.0) | `enquo()`/`enquos()` (12 D2), `obj_address()`, `env_binding_are_lazy()/active()`, weak references for the live-session index, `check_installed()` | `gptr-*`, `env-*`, `session-object` |
| openssl | cryptographic randomness for PKCE and bearer tokens without touching `.Random.seed`, sha256/HMAC, base64 without line breaks (11, 19, 09 SigV4 later) | `auth-*`, `mcp-server`, `utils-ids` |
| yaml | SKILL.md and agent-file frontmatter (05: a hand parser lost 4 of 37 real skills to folded scalars) | `skill-*`, `subagent-defs` |

Base packages used: `grDevices`, `graphics`, `methods`, `stats`, `tools`, `utils`.

### 8.2 Suggests (each guarded by `requireNamespace()` / `rlang::check_installed()` with a base-R fallback or a classed `missing_package` error)

| Package | Feature |
|---|---|
| later, httpuv | background runs; `gptr_mcp_serve()`; OAuth loopback callback (paste fallback without it) |
| shiny, bslib, chromote | artifacts (`gptr$app()`); session check and screenshot (HTTP-only check without chromote) |
| ragg | faster, headless PNG plots (fallback `grDevices::png()`) |
| knitr, rmarkdown | knit_print, stale-chunk hooks, optional engine; vignettes |
| rstudioapi | IDE document backend (14 §4.3) |
| reticulate, DBI, duckdb, RSQLite | `gptr$py()`, `gptr$sql()` (G5) |
| vctrs | delayed S3 methods for System 1 vectors in tidy workflows (04 §4.5) |
| stringi | NFKC in the fuzzy edit fallback; natural sort |
| magick, base64enc | image resize/convert (fallback: send within limits or refuse) |
| keyring, jose | credential backend; ID-token validation for Sign in with ChatGPT |
| otel | optional tracing (INFRA-28) |
| testthat (>= 3.0.0), withr | tests |

### 8.3 System requirements (optional, discovered with `Sys.which()`)

`claude` (Claude Code CLI) and `codex` (Codex CLI) for the subscription providers; a Chrome/Edge
for chromote. Never required; never invoked through a shell.

---

## 9. The model-facing tool surface and the system prompt

### 9.1 Tools and presets

| Preset | Tools | Tool-array tokens (o200k proxy) | Used for |
|---|---|---|---|
| `minimal` | `r`, `read`, `edit`, `write` | 686 (G4 §2.8) | sub-agents, cheap models, non-interactive runs |
| `standard` (default) | minimal + `ask` when a human is present | 686 / ~880 | interactive and programmatic use |
| `readonly` | `read`, `r` (scratch env), plus `grep`, `find`, `ls` tools | ~670 | plan mode |
| `extended` | standard + `grep`, `find`, `ls` tools + `agent` + `apply_patch` (GPT family, opt-in) | ~1,900 | models that underuse code (benchmark-selected per model) |

Schemas (sketches; read/edit/write keep Pi's schemas byte-identical, 01 §4):

```json
{"name": "r", "description": "Run R code in the user's live R session. Objects persist and belong to the user; plots come back as images; execution stops at the first error. Output beyond the budget keeps the first 40% and last 60% and names a gptr$out(id) handle. Helpers: gptr$grep/find/ls/sh/py/sql/app/help/search and gptr$mcp$<server>$<tool>(); a sub-agent is gptr(\"task\", data, model = <m>).",
 "input_schema": {"type": "object", "required": ["code"], "properties": {
   "code":    {"type": "string"},
   "record":  {"type": "boolean", "description": "Record in the user's document (default true); false for throwaway checks."},
   "note":    {"type": "string", "description": "One-line decision, recorded as '## Decision: ...'."},
   "timeout": {"type": "number", "description": "Seconds; best effort."}}}}
{"name": "read",  "input_schema": {"required": ["path"], "properties": {"path": {"type": "string"}, "offset": {"type": "number"}, "limit": {"type": "number"}}}}
{"name": "edit",  "input_schema": {"required": ["path", "edits"], "properties": {"path": {"type": "string"}, "edits": {"type": "array", "items": {"required": ["oldText", "newText"], "properties": {"oldText": {"type": "string"}, "newText": {"type": "string"}}}}, "replaceAll": {"type": "boolean"}}}}
{"name": "write", "input_schema": {"required": ["path", "content"], "properties": {"path": {"type": "string"}, "content": {"type": "string"}}}}
{"name": "ask",   "input_schema": {"required": ["questions"], "properties": {"questions": {"type": "array", "maxItems": 4, "items": {"required": ["id", "question"], "properties": {"id": {"type": "string"}, "question": {"type": "string"}, "type": {"enum": ["single", "multi", "text"]}, "options": {"type": "array", "maxItems": 9, "items": {"type": "string"}}, "default": {"type": "string"}}}}}}}
```

`ask` is 18 §3.6 trimmed (options as plain strings, no per-option descriptions, no `allow_other`
because typing an answer is always allowed): ~190 tokens instead of 336. Opt-in tools (`grep`,
`find`, `ls`, `agent`, `apply_patch`) use 01/11/15/20's schemas with 11's optional fields
(`output`, `sort`, `type`).

### 9.2 Permission classes

| Call | Class | Level (18 §3.8) |
|---|---|---|
| `read` inside the project / outside / protected file | read / read-outside / secret | 0 / 1 / 2 (secret guard) |
| `write`, `edit` inside the project / protected or outside | edit / edit-outside | 2 / 3 |
| `r` | classified per flagged call by `gptr_risk()`: 0 read-only, 1 new objects, 2 overwrite or workspace file writes or network reads, 3 delete, processes, installs, overwriting objects above `gptr.protect_size`, dynamic code, 4 critical | max over calls |
| `gptr$grep/find/ls/read/help/search/describe` inside `r` | read | 0 |
| `gptr$sh/script/bg` | command classifier (G5 table) | 0-4 |
| `gptr$py`, `gptr$sql` | token/keyword classifiers (G5) | 0-3 |
| `gptr$app` | process launch of model-written app code | 3 |
| `gptr$mcp$...` | server annotations (untrusted unless the server is trusted): `readOnlyHint` 0, `destructiveHint = FALSE` 2, none 3 | 0-3 |
| nested `gptr()` (sub-agent) | inherits; child mode can only tighten | parent's |
| `ask` | read | 0 |

### 9.3 Modes

| Level | plan | manual (default) | edits | auto |
|---|---|---|---|---|
| 0 | allow | allow | allow | allow |
| 1 | R: allow in a scratch child env (discarded); other tools: deny | ask | ask | allow |
| 2 | deny | ask | allow for `write`/`edit` inside the project, ask for R | allow |
| 3 | deny | ask | ask | allow |
| 4 | deny | ask | ask | ask (blocked without a UI) |

Deny rules apply in every mode; allow rules never loosen plan and never pre-approve level 4; project
settings may only tighten. The console prompt is one line (NS-1):
`allow? [y]es / [a]lways / [n]o / [?]` where `a` adds a session rule covering exactly the flagged
calls (`r(fn:FindNeighbors,FindClusters)`), `n` optionally takes feedback text that becomes the
tool result, `?` shows the 18 §4.7 detail view, and Ctrl-C aborts the run. Non-interactive asks
are denials with an actionable message; scripts that need autonomy say `mode = auto` (NS-5).

### 9.4 Plan mode and the pending plan (NS-12)

`gptr("Clean up the data directory", mode = plan)` runs with the `readonly` preset. Its final
answer is a `<proposed_plan>` block (Codex's template, 20 §2.11 and §4.2), saved to `.gptr/plans/<date>-<slug>.md` and
kept as the session's **pending plan**. The next non-plan `gptr()` call in the same `envir` and R
process receives it once as an `<attached name="plan">` block (with a printed notice
"using the plan from session s12"); the block header records `plan=s12`. Interactively the plan
run ends with the menu "Execute: [a]uto / [e]dits / [m]anual / [k]eep planning", which continues
the same session. This makes NS-12's two-line example work literally without implicit
continuation of unrelated calls.

### 9.5 System prompt outline (frozen at session start; G4 §3.1 wording adapted)

Two blocks where the provider supports them. Token figures are G4's o200k measurements; changed
sections are marked "est.".

| Tier | Section | Included when | Tokens |
|---|---|---|---|
| T0 | `preamble` ("You are gptr, ... inside the user's live R session") | always | 78 |
| T0 | `tools` (one-line snippets) | always | ~90 |
| T0 | `rules` (Pi's edit guidelines, `=` and `\|>`, compact prints, name what you changed) | always | 262 |
| T0 | `r_session` (runs in the caller's env; small steps; do not overwrite user objects; compose in one call; the `gptr$` helpers incl. polyglot lines from G5; `gptr_return()`; never q/readline) | `r` active | ~430 est. (321 + G5's 297 polyglot, deduplicated) |
| T0 | `r_performance` (short) | `r` active | 127 |
| T0 | `documents` (record/note; edit earlier blocks; S1 in control flow) | history document on | 186 |
| T0 | `system1` | a System 1 route exists | 123 |
| T0 | `modes`, `context` (what context blocks are; instructions precedence; vignette last) | always | 84 + 103 |
| T1 | `addendum` (`.gptr/APPEND_SYSTEM.md`, trusted) | present | <= 1,000 |
| T1 | `skills` (catalog, budgeted) | skills visible | 283 for 4 skills |
| T1 | `mcp` (R signatures of MCP tools, 3,000-token budget, rest via `gptr$search()`) | servers configured | 331 for 9 signatures |
| T1 | `r_env` (R version, cores, RAM, installed fast packages, unloadable packages) | capability probe | 399 |

Replacement: `.gptr/SYSTEM.md` or `.opts$system` replaces preamble/tools/rules (Pi rule);
`gptr_prompt_section()` adds or overrides named sections; mid-session changes are appended section
patches, never re-renders (G4 §4.1). First user message: `<project_instructions>` (AGENTS.md,
CLAUDE.md, then vignette.Rmd) with a cache anchor, `<environment>`, `<mode>`, `<workspace>`,
`<attached>`, `<skill_content>` for preloaded skills, then the prompt.

---

## 10. Walkthroughs

Token figures use the estimator of §14.1 and G4's o200k measurements; they are estimates (no paid
calls were made).

### 10.1 NS-1: interactive session on a 5 GB object

1. `gptr()`, human present -> dispatch step 8 -> `repl_run()` on a new session: `envir =
   globalenv()` (the caller), model `anthropic/claude-sonnet-5-5`, mode `manual`, preset `standard`.
   `.gptr/` exists, so `store_open()` appends the header to `.gptr/sessions/<ts>_<id>.jsonl`; the
   transcript target is the IDE's active script (if the user opted in once) or
   `gptr-session-YYYYMMDD-HHMM.R` (14 §4.5).
2. Banner: `env_summary()` prints `pbmc <Seurat, 3,012,448 cells x 33,538 features, 5.1 GB>` through
   the shipped `gptr_describe.Seurat` method (S4 accessors, address-keyed size cache; no copy; 12 §C4).
3. Prompt -> first user message: `<project_instructions>` (vignette.Rmd, ~200 tokens),
   `<environment>` (~70), `<mode>` (~50), `<workspace>` (~30), prompt (~20). Request 1 = T0 ~1,480
   + T1 ~400 (r_env only) + tools ~880 + ~370 = **~3,100 tokens**, 1 h anchors on T0 and the project
   block (G4 §4.3). Deltas stream through `md_stream`.
4. The model sends one `r` call composing the three steps (the `<r_session>` rule on composition),
   with `note = "resolution 0.8 because 0.4 merged the two monocyte groups"`. `perm_check()`:
   `gptr_risk()` sees `pbmc` overwritten and above `gptr.protect_size` -> level 3 -> ask:
   `allow? [y]es / [a]lways / [n]o / [?]`, noting "not undoable: pbmc 5.1 GB exceeds
   gptr.undo_max_bytes" (no snapshot, so no copy).
5. `y` -> FIFO -> `eval_r()` in `globalenv()`, teed to the console; Ctrl-C would offer the pause
   menu (a steer is delivered after this tool). Result: output with progress bars collapsed, and
   `~ pbmc <Seurat> modified`, `+ markers <data.frame 4,211 x 7>` (~200 tokens). The tool ran more
   than 60 s, so the next tail breakpoint uses the 1 h TTL (G4 §4.3.3).
6. Written: the transcript block (header, code verbatim, `#> 4211 marker genes across 3 clusters`,
   `## Decision:`); JSONL entries for the assistant message, the tool result (with `details`) and a
   `doc_block` record.
7. Request 2 = cached prefix + ~450 new tokens; final answer ~150 tokens.
8. `!dim(markers)` -> passthrough evaluation, queued as a note for the next prompt and written as
   `# direct R (! prefix, no model)` with `#>` output. `/mode auto` -> `mode_change` entry; the next
   message leads with `<mode>`. `/exit` returns the session invisibly; `pbmc` and `markers` stay.
   Totals: ~6,650 input tokens (~3,100 cache reads), ~300 output plus thinking, roughly $0.02.

### 10.2 NS-3: the pipe steers one session

1. The `|>` rewrite nests the calls, so `gptr("Load ...")` runs first: `doc_locate()` finds the
   statement (ordinal 1), no block -> run -> session `s`. `gptr(s, "Now run a PCA ...")` sees a
   session in step 3 -> idle -> follow-up turn, block `call=2`. `model = opus` in the third call ->
   `model_change` entry; `transform_for()` keeps signatures only for the same model, so earlier
   Sonnet thinking becomes text (INFRA-08); one cache miss because caches are model-scoped. All three
   blocks sit under the statement with `session=<id>`.
2. `qc = gptr("Run QC ...", pbmc)` attaches `pbmc` as a quosure described by name (~60 tokens).
   Hand-written R in between is logged by the task callback and shown as `<workspace_changes>`.
3. `qc |> gptr("Use 15% ...")` -> follow-up on `qc`; `qc$value` resolves the designated object by
   name, so later in-place edits stay copy-free (P-C `byname.R`).
4. `gptr_fork(qc) |> gptr("Try 10% ...")` -> `store_fork()` copies the leaf-to-root path into a new
   file naming its parent; no listeners, queues or processes are shared; the block header carries
   `fork=<qc id>`.

### 10.3 NS-4: System 1 in control flow

1. `if (gptr("Is this ... RCT?", abstract, model = jev))`: the resolved model is a classifier ->
   step 6, no session. One state, question `noul`. S1 cache miss -> `POST /v1/systemone` on the
   reactor (key materialised only for `api.typesafe.ai`) -> `noul = 0.97` -> `gptr_decision` TRUE,
   `prob = 0.97`, `meta$model = "jev-1.13.0"`. Nested in `if`: no block; a `decision` event if a
   session is active.
2. 20 abstracts -> 20 states, deduplicated, misses sent 8 at a time with bounded rounds (04a: 20
   requests in 407 ms). `table(is_rct)` and `attr(is_rct, "prob")` work.
3. `choices = c(...)` -> `choice` question; probabilities re-keyed by name (04a); `gptr_choice`
   (character), so `tissue == "liver"` is a plain logical.
4. `while (gptr("Is the residual plot acceptable?", diagnostics(fit), model = jev))`: one state if
   `diagnostics()` returns a list or string; for a data frame the idiom is `I(diagnostics(fit))`.
   Each iteration is one ~300-token Jev request.

### 10.4 NS-6: sub-agents across providers

1. `agents = list(stats = agent(model = opus, skills = statistics), code = agent(model = codex),
   biology = agent(model = gemini, skills = single_cell))` is evaluated with `agent = gptr_agent`
   in the mask -> team session (step 9).
2. `auto` backends: `stats` and `biology` inline (minimal preset + preloaded skill), `code` cli.
   Before spawning `codex exec --json`, `gptr_mcp_serve()` starts on 127.0.0.1 with a bearer token
   in the child's environment and Codex gets `-c mcp_servers.gptr.url=...`; `manual` maps to Codex's
   read-only sandbox because `exec` cannot prompt (08).
3. One reactor: two HTTP streams and one pipe in one `processx::poll()`; inline tool calls go
   through the FIFO, each `r` in an overlay `new.env(parent = envir)` with the binding guard and
   its own RNG stream (15 §4.5); Codex's MCP calls into R are serviced by `later::run_now(0)` in the
   pump.
4. `reviews$stats` is a child session; the team's `$text` joins the three reviews; `gptr_usage()`
   sums children (route `api` inline, `plan-cli` for Codex).
5. `gptr("Summarise this cohort", cohorts, parallel = 4)` -> fan-out: one inline child per element,
   attached as the lazy quosure `cohorts[["A"]]`, four at a time; `summaries$text` is a named
   character vector. Children cost ~1,260 static tokens each instead of ~3,200.

### 10.5 NS-7: the script is the history

1. The block of 10.1 lands in the bound document exactly as NS-7 shows (14 §3.1 grammar).
2. `source("analysis.R")` in a fresh session: `gptr("cluster ...")` matches its statement by content,
   finds a fresh block (`prompt=` hash) -> replayed session, zero tokens (text from `.gptr/cache/s2`
   if kept); `source()` then runs the block as ordinary R.
3. `options(gptr.replay = "live")` asks afresh under `gptr_source()`, knitr or line-by-line IDE
   runs (old block skipped); under plain `source()`/Rscript gptr warns and replays (C-17).
4. The agent rewrites an earlier block with `edit`; `doc-write.R` routes it through the document
   backend and updates `sha=`. A block edited by hand is never overwritten in `auto`.
5. Rmd/qmd get a `gptr-<id>` chunk without `#>` lines; ipynb a cell `id = "gptr-<id>"` from the
   own serializer, never while the notebook is open (14 §4.7).

### 10.6 NS-8: an artifact is a Shiny app

1. `markers` is described in `<attached>` (~120 tokens); the `shiny-bslib` skill is in the catalog.
2. The model `write`s `.gptr/artifacts/marker-explorer/app.R` (~55 lines, ~650 output tokens; level 2),
   then runs `gptr$app("marker-explorer", data = "markers")` in `r` (level 3). `artifact-app.R`:
   static checks, leaf `saveRDS(compress = FALSE)` snapshot into `v001/data/` (cap
   `gptr.artifact.max_bytes`), `v001/R/gptr_data.R`, `run/run.R`; spawns `Rscript run/run.R`
   (supervised, tree cleanup); the child picks the port and publishes it atomically; the parent
   checks HTTP 200, then a chromote session check and a 1000x700 screenshot.
3. The tool result carries `artifact marker-explorer -> http://127.0.0.1:4827 (v001; parse, launch,
   http, session ok)` and the screenshot (~900 tokens); revisions are `edit` + `gptr$app()` (v002,
   same port). The console prints the NS-8 line and opens the viewer; the console stays free.
4. The block records `gptr$app("marker-explorer", data = "markers")` and `#> [app] ...app.R`; replay
   relaunches only when interactive. HTML/JS would cost 3.1-3.7x more tokens and inlining the data
   ~127k (17).

### 10.7 NS-11: a whole workflow that reads like R

1. `prep = gptr(..., pbmc) |> gptr(...) |> gptr(...)`: one session, blocks `call=1..3`.
2. Hand-written lines run as R and feed `<workspace_changes>`.
3. In the loop, `gptr(..., top, model = jev, choices = c(...))` returns one `gptr_choice` per
   cluster, cached per input hash.
4. `if (cell_type == "unclear")`: the nested `gptr("Cluster {cl} has ambiguous markers ({top}) ...",
   pbmc) |> gptr("Prefer canonical markers ...")` interpolates `cl` and `top` (§4.1.4), runs one
   two-turn session and writes a **cassette** (§4.1.7).
5. The final top-level `gptr("Build a Shiny app ...", pbmc)` -> block + artifact; `pbmc` exceeds
   the snapshot cap, so `gptr$app()` errors with advice and the model ships `umap_df` and
   `markers_all` instead.
6. Re-sourcing replays the `prep` blocks, hits the S1 cache, replays cassettes (recorded code
   re-evaluated) and relaunches the app only when interactive: no model call.
7. First run, ~15 clusters, 2 unclear: ~12 System 2 requests (~55k input tokens, ~80% cache reads)
   and 15 Jev requests (~$0.0002); System 2 labelling would add ~15 requests of 3-4k tokens.

---

## 11. Delivery

### 11.1 Milestones (each independently testable offline; network tests opt-in)

| Milestone | Plans | Exit test |
|---|---|---|
| M0 Foundation | P01-P03 | `gptr_check()` passes for every constructor; registry precedence, filters, transactional rollback, fail-closed hooks; zero key bytes in any sink (G6 e2e with fake keys) |
| M1 Wire | P04-P06 | INFRA-01/02/03/05/06/07/08/23 on fixtures and the base-R mock server; conformance of the four adapters plus `fake` |
| M2 Decisions | P07 | NS-4 against a mocked `/systemone`: `if`, `while`, vectorised 100 items capped at 8 concurrent, cache hits make zero requests |
| M3 Live objects | P08-P13 | NS-2, NS-3, NS-5 with the fake provider: code runs in the caller's frame, pipes steer one session, forks do not share listeners; the tracemem suite (gateway, evaluator, snapshots, `$value`); the 20-turn byte-prefix test (G4 §5.9); the permission matrix |
| M4 Harness | P14-P15 | NS-1 through `gptr(.stdin = TRUE)` with scripted input; NS-7 record/replay in `.R`, Rmd, qmd, ipynb; Rscript deferred writes; `gptr_source()` regeneration without double execution |
| M5 Ecosystem | P16-P17 | NS-10: skills preload and catalog budget; a toy plugin package (G1's `gptrpanel` shape) loads lazily; MCP stdio fixture server in both eras; `gptr$mcp$...` calls gated |
| M6 Many agents | P18 | NS-6 with two inline fakes, one worker and one fake CLI interleaving on one reactor; no orphan processes after abort; NS-9 CLI doctor checks |
| M7 Polyglot and apps | P19 | G5's eight polyglot tasks; NS-8 artifact ladder with a fixture app (chromote step skipped when absent) |
| M8 Measured release | P20 | token benchmark baseline committed; NS-11 end to end on the fake provider; `R CMD check --as-cran` clean on the r-lib matrix plus oldrel-4 and no-suggests |

### 11.2 Implementation plans (20, dependency order)

| Id | Title | Scope | R files owned | Depends on |
|---|---|---|---|---|
| P01 | Foundation | DESCRIPTION, NAMESPACE bootstrap, `.lintr`, conditions, ids, encoding, options, paths, text budgets, hashing, JSON, schema validation; an `on_load()` registration helper so later plans add load-time work in their own files | `utils-conditions.R`, `utils-ids.R`, `utils-encoding.R`, `utils-options.R`, `utils-paths.R`, `utils-text.R`, `utils-hash.R`, `json-encode.R`, `json-partial.R`, `json-schema.R`, `zzz.R` | - |
| P02 | Secrets and redaction | vault, handles, redactor with sink profiles, streaming redaction, `.env` loader, credential store | `auth-secrets.R`, `auth-redact.R`, `auth-dotenv.R`, `auth-store.R` | P01 |
| P03 | Registry and extension API | 22 kinds, constructors, registry, precedence, filters, API object, hooks with dispatch semantics, loader (transactional, lazy), `gptr_check()`, versioning | `ext-registry.R`, `ext-specs.R`, `ext-api.R`, `ext-load.R`, `ext-hooks.R`, `ext-check.R`, `ext-builtins.R` | P01 |
| P04 | Reactor and processes | curl multi pool, poll loop over fds and pipes, timers, FIFO, cancellation, SSE/NDJSON splitter, timeouts, retry, rate limiter, process supervision; mock SSE server helper | `proc-supervise.R`, `http-reactor.R`, `http-request.R`, `http-sse.R`, `http-retry.R` | P01, P02 |
| P05 | Messages, catalog, first adapters | message model, events, accumulator, projection and hand-off, provider registry, catalog snapshot and prices, `fake` and `anthropic-messages` adapters | `provider-message.R`, `provider-events.R`, `provider-transform.R`, `provider-registry.R`, `provider-fake.R`, `provider-anthropic.R`, `catalog-models.R`, `catalog-prices.R` | P03, P04 |
| P06 | More adapters and OAuth | `openai-responses` (incl. ChatGPT-plan filter), `openai-completions` + compat table, `google-generative-ai`, PKCE/loopback/refresh | `provider-openai-responses.R`, `provider-openai-completions.R`, `provider-google.R`, `auth-oauth.R` | P05 |
| P07 | System 1 | typed vectors and methods, typesafe adapter with bounded rounds, batch rule, abstention, cache, emulation | `s1-types.R`, `s1-client.R`, `s1-gateway.R`, `s1-emulate.R`, `s1-cache.R` | P05 |
| P08 | Evaluator and introspection | hand-rolled evaluator, plots, guard and symbol shim, snapshots/diffs, describers, task-callback history, tracemem suite | `eval-core.R`, `eval-plots.R`, `eval-guard.R`, `env-snapshot.R`, `env-describe.R`, `env-history.R` | P01, P03 |
| P09 | File tools and the gateway namespace | dispatcher contract, `read`/`write`/`edit` (+ diff, patch envelopes), walker/gitignore/glob, grep/find/ls, `gptr$` namespace with generated closures | `tool-contract.R`, `tool-namespace.R`, `tool-read.R`, `tool-write.R`, `tool-edit.R`, `tool-walk.R`, `tool-grep.R`, `tool-find.R` | P03 |
| P10 | Permissions, UI, ask | risk classifier, policies, modes, rules, persistence, `/undo` under budget, UI backends, compact prompt, `ask` tool | `perm-classify.R`, `perm-gate.R`, `perm-ui.R`, `tool-ask.R` | P08, P09 |
| P11 | Agent loop and sessions | loop with queues and stepping, run states, recovery, session object and accessors, JSONL store, usage and budgets, the `r` tool | `agent-loop.R`, `agent-run.R`, `agent-recovery.R`, `session-object.R`, `session-store.R`, `session-usage.R`, `tool-r.R` | P05, P08, P09, P10 |
| P12 | Context assembly | sections and presets, context blocks, instructions discovery, cache breakpoints and prefix guard, compaction, estimator and ledger | `prompt-sections.R`, `prompt-context.R`, `prompt-instructions.R`, `prompt-cache.R`, `prompt-compact.R`, `prompt-tokens.R` | P11 |
| P13 | Gateway and SDK | `gptr()` dispatch, identifier NSE, interpolation, SDK verbs, config layers, `gptr_init()`, trust, providers/login | `gptr-gateway.R`, `gptr-resolve.R`, `gptr-sdk.R`, `gptr-config.R`, `gptr-setup.R` | P06, P07, P12 |
| P14 | Console | REPL, input grammar, renderer, interrupt policy, slash commands | `console-repl.R`, `console-render.R`, `console-interrupt.R`, `console-commands.R` | P13 |
| P15 | Documents and replay | locate, blocks, atomic writes and IDE backends, formats (R, Rmd/qmd, ipynb, transcript), replay modes, S2 cache, cassettes, `gptr_source()`, knitr integration | `doc-locate.R`, `doc-blocks.R`, `doc-write.R`, `doc-formats.R`, `doc-replay.R`, `doc-knitr.R` | P13 |
| P16 | Skills, templates, agents, plugins | skill discovery and budget, templates, agent definition files, plugin packages and directories | `skill-discover.R`, `skill-templates.R`, `subagent-defs.R`, `ext-plugins.R` | P13 |
| P17 | MCP | client (both eras, stdio/HTTP, OAuth), config import and TOML, `gptr$mcp` namespace and search, server (sdk + HTTP) | `mcp-client.R`, `mcp-config.R`, `mcp-namespace.R`, `mcp-server.R` | P06, P13 |
| P18 | Sub-agents and CLI providers | inline/worker/cli backends, teams, fan-out, `gptr_parallel()`/`gptr_map()`, worker script, `cli-claude`, `cli-codex` | `subagent-backends.R`, `subagent-team.R`, `subagent-worker.R`, `cli-common.R`, `cli-claude.R`, `cli-codex.R` | P16, P17 |
| P19 | Polyglot bridges and artifacts | `gptr$sh/script/bg/jobs/out/py/sql/knit`, interpreter kind, `gptr$app()` and the artifact registry | `bridge-sh.R`, `bridge-lang.R`, `artifact-app.R`, `artifact-registry.R` | P10, P13 |
| P20 | Measured release | token benchmark suite and baselines, perf benchmarks, vignettes, README, NEWS (1.0.0 breaking changes), cran-comments, CI matrix | none in `R/` (dev/bench, vignettes, docs) | all |

---

## 12. Risks, mitigations and deferrals

### 12.1 Risks

| Risk | Mitigation |
|---|---|
| In-process evaluation cannot be sandboxed; `auto` mode can damage the session or files | Modes, rules, critical and secret guards, protect-size escalation; documented "not a security boundary" (18, G6); `manual` default |
| Interrupt and readline behaviour unverified in RStudio, Positron, Jupyter, Windows (02, 18) | Manual test matrix before documenting; UI abstraction lets a front end replace the prompt; non-human contexts never show a menu |
| Windows untested throughout (processx `.cmd` shims, CTRL+BREAK, file locks, encodings) | Windows CI job from M1; refuse `.cmd` shims; binary I/O everywhere; UTF-8 marking before JSON |
| Claude plan bridge's policy status UNCERTAIN (07) | Opt-in, notice, unmodified CLI only, no credential access; maintainer to ask Anthropic before CRAN release; `claude_code` alias can be renamed without breaking the provider id |
| Sign in with ChatGPT is a preview; plan-mode request rules may shift (08) | Behind `gptr_login("chatgpt")`; request filter is data; Codex CLI route stays available |
| MCP spec churn (two breaking eras in eight months, 16) | Thin protocol layer, era probe, spec-example fixtures in tests |
| Token estimates are o200k proxies; Claude/Gemini tokenizers private (21, G4) | Provider-reported usage is authoritative; the live benchmark mode refits estimator coefficients per provider |
| Replay executes recorded code (blocks, cassettes) | Only code that ran before under the user's mode in this project; `gptr_blocks()`/`gptr_cache("show")` expose it; `GPTR_REPLAY=live` or deleting a block regenerates |
| Nested-call cassettes may become stale or surprising | Keys include the interpolated prompt and a context digest; `gptr_cache("clear", "s2")`; `replay = "live"` per call |
| Prompt interpolation false positives (LaTeX with bound single letters) | Only `{identifier}` of atomic bound values in literal prompts; `{{x}}` escape; `interpolate = FALSE`; the interpolated prompt is visible in the transcript |
| Four-tool default may underperform on models that prefer dedicated search tools | Benchmark per model family (§14.5); presets switchable per model in settings (`tools.preset` keyed by model pattern) |
| Sticky references reintroduced by future code or R versions (12) | Fresh-process tracemem suite over every entry point on R-release and R-devel in CI |
| Inline sub-agents can still mutate reference objects (environments, data.table, Seurat internals) | Classifier flags by-reference mutation; worker backend for isolation; documented |
| Long R computations outlive the 5-minute cache TTL (G4 §2.9) | Adaptive 1 h tail TTL after tools longer than 60 s or when objects > 1 GB exist |
| CRAN reviewer objects to top-level evaluation reaching the caller's frame or to document writes (13) | Consent by `gptr_init()`/interactive yes; tempdir without a workspace; examples with `envir = new.env()` and the fake provider; the precedents btw, aisdk (13 §1) |
| Plugins run arbitrary code in the session | Opt-in enabling, trust gating, fail-closed policies; project filters cannot disable user or built-in policies (G1 §3.6) |

### 12.2 Deferred beyond v1

Fork backend; Codex app-server driver; Gemini Interactions API; Bedrock Converse with SigV4 and
Vertex (Bedrock's OpenAI-compatible endpoint works in v1 through the compat table); Copilot and
other impersonation providers (never in core); a Shiny or shinychat front end and an RPC front end
beyond the worker JSONL protocol; `mori`/`mirai` worker accelerators; worktrees and file locking
for parallel agents editing one tree; todo/plan-tracking tools; LSP; provider-side compaction and
clearing (opt-in plugins later); MCP sampling, legacy SSE resumption and Client ID Metadata
Document hosting; `pack = TRUE` System 1 batching; Jupyter `set_next_input`; Rcpp routines (watch
list in 21); an `apply_patch` default for GPT models (plugin exists, off, pending benchmark); the
`{gptr}` knitr engine default (plugin exists, off, pending maintainer).

---

## 13. Extensibility map (S-11)

### 13.1 Every capability category

Every row registers through `gptr$register(spec)` inside a `function(gptr)` factory, `gptr_register()`
at top level, a call argument (rank 0), or declarative files; every built-in listed is itself loaded
by `ext_load()` as a `builtin:*` extension and can be overridden or disabled (`-builtin:<name>`,
`-<kind>:<name>`), except that project settings cannot disable policies or hooks of the user or
built-ins.

| Category | Registration and contract | Built-ins implemented on it | How an R package ships it | What a third-party agentic layer does with it |
|---|---|---|---|---|
| Native HTTP providers | `gptr_provider(id, api, base_url, auth, models, compat)`; data bound to an adapter; `auth` a zero-arg resolver returning a secret handle | `builtin:providers`: anthropic, openai, google, OpenRouter, Groq, DeepSeek, Mistral, Together, Ollama, LM Studio, vLLM, Azure, Bedrock-compat | `inst/gptr/plugin.json` provides `provider`; factory registers records | Add an internal gateway by data alone |
| Wire adapters | `gptr_adapter(api, transport, build, parse)`; never throws after `start`; conformance with wire fixtures | `anthropic-messages`, `openai-responses`, `openai-completions`, `google-generative-ai`, `typesafe-system-one`, `cli-claude`, `cli-codex`, `fake` | exported factory + fixtures for `gptr_check()` | Bring a new wire format (e.g. Converse) |
| Subscription CLI providers | `gptr_provider(type = "cli")` + `process_jsonl` adapter with a control handler | `cli-claude`, `cli-codex` | same | Drive another agent CLI as a sub-agent |
| System 1 providers | `gptr_provider(type = "classifier")` + adapter `classify(model, state, questions, options)` returning probabilities | Jev direct, OpenRouter, Vercel; emulation adapter | same | A domain classifier used as `model = mymodel` in `if()` |
| Model routers | `gptr_router(name, route)`; `route(request, ctx)` -> registered model within 50 ms; errors fall back | `builtin:jev-router` (off by default; Pi's complexity router) | factory | Cost-aware routing, `model = cheapest` |
| Models | `gptr_model(id, provider, ...)` catalog entries | shipped snapshot | `inst/gptr/models.json` | Private fine-tunes |
| Tools (model-visible) | `gptr_tool(..., exposure = "direct")`; `execute(input, ctx)`; never-throw dispatch; risk function | `r`, `read`, `edit`, `write`, `ask`; opt-in `grep`, `find`, `ls`, `agent`, `apply_patch` | factory | Domain tools with their own risk classes |
| Namespace members (`gptr$...`) | `gptr_tool(..., exposure = "r", fun =)`; one signature line in the prompt (36 vs 328 tokens, G1 §2.5) | `read`, `write`, `edit`, `grep`, `find`, `ls`, `sh`, `script`, `bg`, `jobs`, `out`, `py`, `sql`, `knit`, `app`, `help`, `search`, `describe`, `mcp` | factory; lazy via manifest `declarations` so the signature is in the cached prefix before activation | Whole toolkits callable from model code (`gptr$trials$search()`) |
| Interpreters | plugin-defined kind `interpreter` (`gptr_kind()` + `gptr_spec("interpreter", ext, candidates, args)`) | `.sh`, `.py`, `.R`, `.js`, `.pl`, `.rb` for `gptr$script()` | factory | Julia, Stata, SAS runners |
| MCP servers | `gptr_mcp_server(name, command \| url, exposure = "r")`; `mcp.json` shape | `builtin:mcp` (replaceable) incl. import of other harnesses' configs | `inst/gptr/mcp.json` | Bundle a server with a domain package |
| Skills | Agent Skills folders; `gptr_skill(path)` | `high-performance-r`, `shiny-bslib`, `gptr-orchestration` | `inst/gptr/skills/<name>/SKILL.md` (also `inst/skills`) | Domain playbooks, auto-available when the package is attached |
| Prompt templates | `gptr_prompt_template(name, text)`; `/name args` | `explain`, `review` | `inst/gptr/prompts/*.md` | Team conventions |
| Slash commands | `gptr_command(name, handler)` | `builtin:commands` (18 §4.4 list) | factory | `/panel`, `/deploy` |
| Hooks and events | `gptr_hook(event, handler)`, `gptr$on()`, `gptr_on(session, ...)`; Pi dispatch semantics; fail-closed events | session store, document writer, console renderer, usage accounting, cache-break detector are hooks | factory (activation `eager` for audit loggers) | Observability, auditing, custom transcripts |
| Permission policies | `gptr_policy(name, check)`; deny > ask > modify > allow; throwing denies | `builtin:permissions` (mode, rules, critical guard, secret guard, protect size) | factory | Org policy packs, a System 1 reviewer answering asks via `permission_request` |
| UI backends | `gptr_ui(name, select, input, questions, notify, has_ui)`; failing dialog = not approved | console, none, scripted, rpc | factory | RStudio dialogs, Shiny gadget |
| Context blocks | `gptr_context_block(name, provide, placement, budget)`; within budget; no promise forcing | `environment`, `workspace`, `workspace_changes`, `attached`, `mode`, `project_instructions` | factory | Lab-notebook or database-schema context |
| Object describers | S3 `gptr_describe(x, budget)`; leaf discipline | default, data.frame, matrix, list, environment, function, lm/glm, S4, Seurat, SingleCellExperiment, dgCMatrix, data.table, Arrow, DBI | `S3method(gptr::gptr_describe, myclass)` (works with gptr in Suggests) | Cheap, accurate descriptions of domain objects |
| Prompt sections | `gptr_prompt_section(name, text, tier, order, budget)`; stable across turns | all T0/T1 sections of §9.5 | factory | House rules, domain preambles |
| Compaction strategies | `gptr_compactor(name, should, compact)`; reports usage; errors fall back | two-stage checkpoint (G4) (replaceable) | factory | Provider-native compaction |
| Document formats and history writers | `gptr_doc_format(name, ext, locate, render, write)`; `document_write` event | `r`, `rmd`, `qmd`, `ipynb`, `transcript` (replaceable) | factory | Org-mode or Word lab records |
| Artifact types | `gptr_artifact_type(name, build, check, launch, stop)` | `shiny`, `html` | factory | Plumber APIs, Quarto dashboards |
| Sub-agent backends | `gptr_backend(name, start, poll, cancel, capabilities)`; never block the reactor > 50 ms; cancel kills the tree | `inline`, `worker`, `cli` | factory | mirai or cluster backends |
| Agent definitions | `gptr_agent(...)`; `.gptr/agents/*.md` (Claude-compatible frontmatter) | `reviewer`, `explorer` | `inst/gptr/agents/*.md` | Named specialists used in `agents =` |
| Front ends | `gptr_frontend(name, run)` | console REPL, knitr (`knit_print`), JSONL (workers) | factory | An RPC server, a Shiny chat |
| Settings | `gptr_setting(name, default, scope, validate)` | core settings | factory | Plugin configuration through `gptr_config()` |
| Secret sources and redaction rules | `register_secret_source()`, `register_redaction_rule()`, `register_env_alias()`, `register_child_env()` (G6) | `.env`, environment, auth.json, keyring | factory | PHI/identifier redaction for clinical data |
| New kinds | `gptr_kind(name, validate, resolve)` + `gptr_spec()` | `interpreter` (above) | factory | Entire new capability categories |

A third party building an agentic layer (an orchestrator, a review panel, a workflow engine) needs
only exported verbs: `gptr(.run = FALSE)`, `gptr_step()`, `gptr_wait()`, `gptr_on()`,
`gptr_steer()`, `gptr_fork()`, `gptr_parallel()`, `gptr_usage()`, plus `ctx$decide()` (System 1
inside plugins, part of API 1.0) and the constructors (G1 §4.6 verified with the toy `gptrpanel`).

### 13.2 API versioning policy (G1 §4.5)

`gptr_api_version()` starts at 1.0 with gptr 1.0.0 and changes only when the extension API
changes. MINOR is additive (new kinds, events, members, optional fields; handlers must ignore unknown
payload fields). MAJOR is breaking and requires the CRAN notice period to reverse dependencies found
with `which = "most"`. Requirements use caret semantics (`"1.2"` means `>= 1.2, < 2`) and are
read from the manifest, `Config/gptr/api` in DESCRIPTION, the factory attribute, and
`gptr$require()`. Plugins negotiate features with `gptr$has("kind.router")`. Deprecations warn once
per session with class `gptr_deprecated` and live at least one MINOR release and six months. An unmet
requirement or failing factory disables only that plugin (diagnostic in `gptr_registry(diagnostics =
TRUE)`). `artifact_type`, `frontend`, `interpreter` and plugin-defined kinds are marked
experimental in 1.0.

---

## 14. Token-efficiency analysis (S-12)

### 14.1 Estimation and calibration

Provider-reported usage is authoritative up to the last response; entries added since then are
estimated (21 §2.8, G4 §4.5): prose and R/other code chars/4; printed R output, CSV, JSON and tool
results chars/2 (chars/4 underestimates printed R by 51%, CSV by 58%, JSON by 45%); CJK 1 token per
character; images by provider formula (Anthropic `ceil(w/28) * ceil(h/28)`: 768x512 = 532 tokens).
No tokenizer ships (rtiktoken is dev-only for the benchmark). Budgets for helper prints use G5's
fitted per-byte-class coefficients with a 0.85 safety factor.

### 14.2 Static cost per preset (tools + system prompt, o200k proxy)

| Preset | Tools | T0 system | T1 (fixture: 4 skills, 2 MCP servers, r_env) | Static total |
|---|---|---|---|---|
| minimal (sub-agents) | 686 | 572 | 0-400 | 1,258-1,660 (G4 measured 1,258) |
| standard, no human | 686 | ~1,480 est. | ~1,010 | ~3,180 |
| standard, interactive (+ ask) | ~880 | ~1,490 | ~1,010 | ~3,380 |
| G4 default (7 tools) for comparison | 1,199 | 1,386 | 1,013 | 3,598 |
| extended | ~1,900 | ~2,160 | ~1,010 | ~5,070 (G4 measured 5,066) |

First request of a session adds the first user message (project instructions ~220, environment
~70, mode ~50, workspace ~120 for six objects, prompt): **~3,700 tokens** for the standard preset,
against 4,061-4,137 for G4's default and 3-18K for the Claude Code CLI's own prompt (07). Later
requests re-read this prefix from cache (0.1x input price; 0.05x on Opus 5.5, 07).

### 14.3 Environment description and typical results

| Item | Tokens | Budget |
|---|---|---|
| `<workspace>` with 6 objects (one line each, largest first) | 122 (G4) | 600 |
| One object in `<attached>` (header, column types, 3 rows) | 60-150 | 300 |
| `<workspace_changes>` after user code | ~70 | 300 |
| Typical `r` result (`dim()` + `head()` of a data frame, ~360 printed chars) | ~190 | 2,000 (then head/tail + `gptr$out(id)`) |
| `r` result with one plot | ~200 + 532 | - |
| `gptr$grep()` with 20 matches | ~300 | 1,500 print budget |
| Artifact result (text + 1000x700 screenshot) | ~80 + ~900 | - |
| System 1 request (Jev input) | 250-280 overhead + state | 32k state limit |

### 14.4 One north-star task end to end (NS-1)

| Request | Input | of which cache read | Output |
|---|---|---|---|
| 1 (prompt) | ~3,100 (no skills/MCP) | 0 (written, 1 h anchors) | ~150 (one composed `r` call + note) |
| 2 (after the tool result) | ~3,550 | ~3,100 | ~150 (answer) |
| `!dim(markers)`, `/mode auto` | 0 | - | - |

About 6,650 input tokens (~3,100 cache reads), ~300 output tokens plus thinking; roughly $0.02 on
Sonnet 5.5 (1 h cache writes at 2x input dominate the first request; every later turn in the hour
pays 0.1x for the prefix). A bash-and-Rscript harness would re-load the 5 GB object on every script run (the
reason REQ-01's headline benefit exists) and pay its own 3-18K-token prompt per request (07).

### 14.5 What each design choice saves

| Choice | Saving | Evidence |
|---|---|---|
| Four model-visible tools; search as `gptr$grep()` | 513 schema tokens per uncached request vs the 7-tool set; 352 more by not declaring `artifact` | G4 §2.8 |
| Namespace members and MCP tools as R signatures | 36 vs 328 tokens per tool (9x); 5,899 vs 143,525 characters for Claude Code's MCP tool list | G1 §2.5, 16 §summary |
| Composition in one `r` evaluation | SQL in 3 steps: 6,476 -> 175 tokens; 8 polyglot tasks: 45,140 (bash tool) -> 7,592 (same command via `gptr$sh`) -> 1,967 (R-composed); fewer round trips | G5 token table |
| Shiny instead of HTML/JS for apps | 3.1-3.7x fewer tokens; data referenced by name instead of inlined (~127k tokens) | 17 |
| Frozen, cache-anchored prefix; append-only transcript | 2.7x cheaper than rebuilding the system prompt per turn ($0.323 vs $0.876 in the 20-turn simulation) | G4 §2.9 |
| No in-place micro-compaction | 32% cheaper session; no invalidated thinking | G4 §2.10 |
| System 1 for judgements | ~280 Jev tokens at $0.042/M vs ~600-3,000 System 2 tokens at $2-4/M per item; 20 items in ~0.4 s | 04, 04a |
| Plot images at 768x512 | 532 vs ~900 tokens per plot | 12 §3.5, 17 |
| `r` output budget 2,000 tokens with head/tail and a handle | Pi's 50 KB limit is ~25k tokens of printed R (1.94 chars/token); handle notice 30 vs 69 tokens | 21 §2.8, G5 |
| Edit results without a diff unless something deviated | up to ~1,000 tokens per edit (4 KB diff cap) | 11, 20 |
| Interpolating `{cl}`/`{top}` instead of attaching them | ~60-120 tokens per call in loops | §4.1.4 |
| Skills catalog budget and activation through `read` | catalog capped at max(8000 chars, 1% window) vs 16k tokens on the test machine; no skill tool whose enum would break the cached tool array | 16, G1 |
| Minimal preset for sub-agents | ~1,260 vs ~3,200 static tokens per child | G4 |
| Sign in with ChatGPT instead of Codex for the ChatGPT plan | avoids 19-38K extra input tokens per Codex turn | 08 |
| Secret markers `[secret:NAME]` | 6-10 tokens vs 26-104 for a real-format key | G6 |

### 14.6 Accounting, budgets and the benchmark suite

- **Usage records** per request with route and cache-write TTL split (§5.5, INFRA-20);
  `gptr_usage(x, by =)` aggregates sessions, teams, children and the S1 log.
- **Token ledger** per request (`gptr_usage(s, detail = TRUE)`, `/context`): tokens by component
  (T0, T1 by section, tools, project block, environment, workspace, attached, transcript, tool
  results, images), marking which were cache reads. `gptr_registry()` shows each capability's
  declaration cost.
- **Budgets**: `budget = list(tokens =, cost =, turns =)` per call, session defaults in settings,
  children inherit a share; the loop checks before each request and stops at a turn boundary with
  `status = "budget"` and a `budget_exceeded` event. Output budgets: `r` 2,000 tokens, helper prints
  1,500 (G5), describe 300 per object, workspace 600, MCP signatures 3,000, hook-injected context
  10,000 characters (20).
- **Prefix guard**: each request is compared with the previous one for the same model; a broken
  byte prefix emits `cache_break` naming the culprit (G4 §4.3.5); a package test (CRAN-safe) runs
  G4's 20-turn scenario and asserts the prefix property.
- **Benchmark suite** (`dev/bench/tokens/`): scenarios for NS-1 to NS-11 and G5's polyglot tasks
  run against the fake provider with scripted model turns (authored once, refreshed from live runs
  under `GPTR_LIVE_TESTS=true`). It records per-request tokens (rtiktoken o200k), cache-read share,
  round trips and simulated cost; baselines are committed; CI fails when the first request of the
  standard preset grows by more than 5% or a scenario's total by more than 10% (G4 §4.9, G5). The
  same suite decides per-model presets (`extended` vs `standard`) and whether `apply_patch` becomes
  a default for GPT models.

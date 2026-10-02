# P-A — Lean R-native core

Architecture proposal for gptr 1.0.0. Lens: the smallest correct core that satisfies every
requirement (REQ-01..REQ-42), honours S-1..S-12, and can ship to CRAN and be maintained by a small
team. Author: design agent P-A, 2026-09-29.

Evidence conventions: `[NN §x]` cites `dev/research/NN-*.md` section x; `[10a INFRA-nn]` cites a
requirement of the infrastructure review; `[G1]`, `[G4]`, `[G6]` are gap reports (G1 and G4 had no
verification log when this proposal was written, so their measured numbers are used as estimates and
their designs are re-checked against the verified reports they cite). `[P-A exp]` marks an experiment
run for this proposal in `scratchpad/work/design/P-A/` with `Rscript --vanilla`.

---

## 1. Pitch and design principles

**Pitch.** gptr 1.0 is one function, one object and one registry. `gptr()` is the only gateway; what
it returns is the agent session itself, an environment with reference semantics, so `|>` steers the
same conversation, `$value` holds the R object the agent handed back, and `if (gptr(..., model = jev))`
works because System 1 calls return ordinary typed vectors. Underneath sits a deliberately small
kernel (a curl-multi reactor, an append-only transcript, a never-throw tool dispatcher and a
copy-safe R evaluator) and a single registry of 19 capability kinds. Every feature a user sees
(providers, tools, permissions, plan mode, ask-user, skills, MCP, documents, artifacts, sub-agents,
the console) is a built-in plugin registered through the same public, versioned call a third-party
package would use. Seven Imports, no compiled code, no R6, no httr2. The model sees four tools by
default (read, write, edit, r) plus `ask` when a human is present; everything else, including grep,
MCP servers, plugin tools, Shiny artifacts, shell programs, Python, SQL and sub-agents, is an R
function the model composes inside one `r` call. That is the token-efficiency thesis of the whole
package: R is the compression layer.

**Principles (how the lens shapes every decision).**

| # | Principle | Consequence in this design |
|---|---|---|
| P1 | One gateway, one object | `gptr()` dispatches on its arguments (S-1); it returns a `gptr_session` environment (S-8); System 1 returns typed vectors; there is no `gptr_result` list [12 §3.10 overturned by S-8, 10a INFRA-14]. |
| P2 | Small kernel, everything else a plugin | Kernel = reactor, message model, loop, dispatcher, evaluator, store, registry. Everything else registers as `builtin:<name>` through `gptr_register()`/`api$register()` and can be replaced or disabled with a filter (S-11) [G1 §4.2]. |
| P3 | Base R first, few dependencies | Imports: jsonlite, curl, processx, callr, rlang, cli, yaml (7; closure 9 non-base packages plus otel with callr 3.8.0) [P-A exp]. No httr2 (its streaming paths fail INFRA-01/03 [10a E1-E3], its parallel path retries without bound [04 §2.16]). No R6/S7 in code [G1 §2.3, 10a §16]. No Rcpp [21]. |
| P4 | Own the wire, one loop | Every byte of provider traffic, System 1 fan-out, MCP-over-HTTP and child-process pipes goes through one `processx::poll()` reactor over curl multi handles with `pipewait = 0` [15 §4.1, 10a INFRA-01/16]. |
| P5 | Append, never edit | Transcript, JSONL store, S1/S2 caches and console transcripts are append-only; the system prompt and tool array are frozen per session; compaction appends a checkpoint [07 §2.5, G4 §2.7]. |
| P6 | Copy-safety is an invariant | The harness never holds a reference to a user object: introspection by name through primitive leaves, snapshots of addresses and fingerprints only, no `mget()` snapshots of large objects, no binding locks [12 §2.C, P-A exp]. A fresh-process tracemem suite guards it. |
| P7 | Tokens are a budget, not an afterthought | Each prompt section, context block, tool schema and tool result has a budget; the default model-visible surface is four tools; the rest is reached through `gptr_tools$...` at about 36 tokens per function instead of about 328 per direct tool [G1 §2.5]; a token benchmark fails CI on regressions. |
| P8 | Honest failure, fail closed | Tools and providers never throw into the loop (INFRA-02/10); aborted turns are persisted and projected out (INFRA-04); a permission `ask` with no human stops the run with a classed error (north-star §12). |
| P9 | Consent before disk | `.gptr/` exists only after `gptr_init()` or an interactive yes; without it sessions, caches and artifacts live in `tempdir()` [13 §2]. |
| P10 | Ship v1, defer the rest explicitly | Background jobs, the in-session HTTP MCP server, Codex app-server, Sign in with ChatGPT, the knitr engine, apply_patch, fork workers and Pi-file import are v1.x (section 12). No headline benefit is deferred. |

The three headline benefits map to the kernel as follows: in-memory compute is the evaluator plus
the environment policy (P6); System 1 + System 2 is one gateway with two adapter kinds over one
reactor (P1, P4); the R ecosystem is `gptr_tools`, Shiny artifacts and runnable documents (P2, P7).

---

## 2. Architecture overview

Seven layers. A layer may call only layers below it. Built-in plugins (L5) register only through
the L2 extension API and read session services only through `ctx`; they may call lower-layer
internal helpers that a third-party plugin can reach equivalently through `ctx` or an exported
function (the rule that keeps "built-ins are plugins" honest).

```text
L6  PUBLIC API        gptr()  gptr_*()  gptr_tools (dispatcher object)
                          |  NSE capture (rlang::enquos), dispatch, config, init
--------------------------+----------------------------------------------------------------
L5  BUILT-IN PLUGINS  builtin:providers  builtin:tools  builtin:permissions  builtin:plan
    (registered via   builtin:ask  builtin:skills  builtin:prompts  builtin:mcp  builtin:subagents
     the L2 API,      builtin:artifacts  builtin:documents  builtin:console  builtin:store
     replaceable)     builtin:compaction  builtin:context  builtin:system1
--------------------------+----------------------------------------------------------------
L4  AGENT KERNEL      session object + store (JSONL v3 tree, append-only)
                      request assembly (frozen system, render-once entries, prefix guard)
                      agent loop (state machine, steer/follow-up queues, budgets, max_turns)
                      tool dispatcher (validate -> gate -> execute; never throws; FIFO)
                      evaluator (copy-safe R eval, plots, guard)   workspace snapshot/describe
--------------------------+----------------------------------------------------------------
L3  MODEL LAYER       message model + hand-off transform   usage/cost   catalog + resolver
                      adapters: anthropic-messages | openai-responses | openai-completions |
                      google-generative-ai | typesafe-system-one | cli-claude | cli-codex | fake
                      System 1 typed vectors (gptr_decision / gptr_choice / gptr_score)
--------------------------+----------------------------------------------------------------
L2  EXTENSION API     registry (kind, name) x rank; spec validation; filters; diagnostics
                      loader (factories, transactional, lazy plugins, manifests)
                      event bus (dispatch semantics, fail-closed events)   ctx
--------------------------+----------------------------------------------------------------
L1  PLATFORM          reactor (curl multi + processx::poll + timers + admission + rate limits)
                      SSE/NDJSON byte splitters, partial JSON   process helpers (write-all,
                      kill_tree, .cmd shims)   secrets (vault, dotenv, redaction, child env)
--------------------------+----------------------------------------------------------------
L0  UTILS             conditions  ids (no RNG)  JSON encode/UTF-8 marking  atomic raw I/O
                      truncation + spill files  token estimator  options/interactivity
```

Data flow for one programmatic call `gptr("...", x)`:

```text
gptr() --capture--> resolve ids --route--> session (new or continued)
   |                                             |
   |   first user entry: project block, environment, mode, workspace, attached x, prompt
   v                                             v
agent loop --request spec--> reactor --curl--> provider --SSE bytes--> decoder --events-->
   ^                                                                     |
   |  tool results (source order)       tool calls <---------------------+
   +---- dispatcher: validate -> policies/tool_call hooks -> execute (r: evaluator in envir)
                                         |
events: message_end / tool_result / agent_end --> builtin:store (JSONL) , builtin:documents
                                                   (block below the call), builtin:console
```

Allowed dependencies (enforced by a test that greps call sites per file prefix):

| From \ may call | L0 | L1 | L2 | L3 | L4 | L5 | L6 |
|---|---|---|---|---|---|---|---|
| L0 utils | yes | - | - | - | - | - | - |
| L1 platform | yes | yes | - | - | - | - | - |
| L2 extension API | yes | yes | yes | - | - | - | - |
| L3 model layer | yes | yes | yes (registry lookups) | yes | - | - | - |
| L4 kernel | yes | yes | yes (events, ctx) | yes | yes | - | - |
| L5 built-ins | yes | yes | yes (register, on) | yes | yes (via ctx/public verbs) | no cross-plugin calls except through the event bus or registry | - |
| L6 public API | yes | yes | yes | yes | yes | - (only by kind lookup) | yes |

Execution model. R is single-threaded; concurrency is cooperative. One reactor per top-level
`gptr()` call owns all transfers and child processes of that call and its sub-agents. Tools that
evaluate R or touch files run one at a time from a FIFO on the main thread; while one runs, other
agents' bytes buffer in curl and are delivered within about 50 ms after it returns [15 §2.3].
Nothing runs when no `gptr()` call is active (no `later` loop in v1).

Package-global state is limited to (INFRA-15): the registry and catalog (configuration), the secret
vault [G6 §4.1], the artifact process table (to stop children on exit), `the$stack` (the dynamic
"currently executing run" pointer, set and restored by `on.exit`, used by nested `gptr()` and
`gptr_return()`), and `the$last` (one reference to the most recent session, for `gptr_last()`). Usage,
queues, abort flags and caches of in-flight state live in sessions and runs.

---

## 3. Package file layout

### 3.1 `R/` (one topic per file, `<area>-<topic>.R`; 64 files)

Area prefixes (confirming conventions §3 with one addition, `ext`, already listed): utils, json,
http, auth, catalog, provider, cli, s1, ext, session, agent, prompt, eval, env, tool, perm, skill,
mcp, subagent, artifact, doc, console, gptr, plus `zzz.R`.

| File | Layer | Responsibility |
|---|---|---|
| `utils-conditions.R` | L0 | `gptr_abort()/gptr_warn()/gptr_inform()` with class `gptr_error_<class>`; condition redaction hook |
| `utils-ids.R` | L0 | RNG-free ids: `cli::hash_sha256(time-us, pid, counter, salt)`; session, entry, block (6-hex with a-f) ids |
| `utils-text.R` | L0 | UTF-8 marking, ANSI strip, head 40% / tail 60% truncation, spill files, width-safe formatting |
| `utils-fs.R` | L0 | raw-byte read/write, atomic write (temp in same dir + `file.rename`), `dir.create` locks, path guard |
| `utils-tokens.R` | L0 | `est_tokens(x, kind)` (prose/code chars/4, output chars/2, CJK 1/char), budget helpers |
| `utils-options.R` | L0 | option defaults, `gptr_has_human()`, verbosity, front-end detection |
| `json-encode.R` | L0 | `json_encode()`, serialise-once cache (`json_verbatim`), canonical JSON (radix key order), `as_utf8_deep()` |
| `json-partial.R` | L1 | incremental partial-JSON scanner for streamed tool arguments (throttled preview) |
| `http-reactor.R` | L1 | reactor: curl pool, `processx::poll`, timers, admission (`max_active`), per-provider limiter, cancel/cleanup |
| `http-request.R` | L1 | request spec to curl handle (`pipewait = 0`, connect/first-byte/idle timeouts), retry policy, Retry-After |
| `http-sse.R` | L1 | vectorised byte-level SSE and NDJSON splitters (`grepRaw` boundaries), final-event flush |
| `http-process.R` | L1 | processx helpers: write-all loop, line reader, UTF-8, `.cmd` shim via `cmd.exe /d /c call`, grace + `kill_tree` |
| `auth-secrets.R` | L1 | vault, `gptr_secret` handles, credential resolution per request, origin binding [G6 §4.3] |
| `auth-dotenv.R` | L1 | `.env` parser (BOM, CRLF, export, quotes, hyphenated names), alias table, `gptr_env()` |
| `auth-redact.R` | L1 | `redact()` with sink profiles, streaming hold-back, condition redaction, child-environment profiles |
| `auth-oauth.R` | L1 | PKCE S256, loopback (httpuv, Suggests) or paste flow, token store 0600, locked refresh (MCP OAuth) |
| `catalog-models.R` | L3 | snapshot load, merge layers, resolver `provider/id[:thinking]`, aliases, `gptr_models()` |
| `provider-registry.R` | L3 | built-in provider records (data), compat flags, `gptr_providers()` |
| `provider-messages.R` | L3 | message and block constructors, validation, projection (drop aborted, close orphans), hand-off transform |
| `provider-usage.R` | L3 | usage records, cost (TTL-split cache writes), route attribution, `gptr_usage()` |
| `provider-anthropic.R` | L3 | adapter `anthropic-messages` (build, decoder, cache breakpoints, operator messages) |
| `provider-openai.R` | L3 | adapter `openai-responses` (stateless, encrypted reasoning replay, developer items) |
| `provider-completions.R` | L3 | adapter `openai-completions` + compat table (OpenRouter, Ollama, Groq, DeepSeek, vLLM, ...) |
| `provider-gemini.R` | L3 | adapter `google-generative-ai` (thought signatures, finish reasons) |
| `provider-fake.R` | L3 | scripted fake adapter, `gptr_fake_provider()` |
| `cli-claude.R` | L3 | adapter `cli-claude`: stream-json, control protocol, in-process `sdk` MCP bridge, can_use_tool |
| `cli-codex.R` | L3 | adapter `cli-codex`: `codex exec --json -`, event normaliser, sandbox mapping |
| `s1-types.R` | L3 | `gptr_decision`, `gptr_choice`, `gptr_score`: constructors and base/vctrs methods |
| `s1-client.R` | L3 | adapter `typesafe-system-one`, question building, vectorised fan-out on the reactor, bounded rounds, cache |
| `s1-emulate.R` | L3 | opt-in emulation through a System 2 model's structured output (uncalibrated flag) |
| `ext-registry.R` | L2 | registry, 19 kinds, `gptr_spec()`, `gptr_tool()`, `gptr_register()`, `gptr_registry()`, ranks, filters |
| `ext-loader.R` | L2 | factories, transactional load, plugin discovery (`inst/gptr/plugin.json`), lazy activation, `gptr_api()` |
| `ext-hooks.R` | L2 | event catalogue, dispatch semantics, fail-closed events, `gptr_on()` |
| `ext-ctx.R` | L2 | `ctx` object handed to every handler (session services, UI, risk, redact, decide) |
| `ext-check.R` | L2 | `gptr_check()` conformance suites for specs, factories and packages |
| `ext-builtins.R` | L5 | the list of built-in factories and their registration at load |
| `session-object.R` | L4 | `gptr_session` class, `$`/`$<-`/`[[`/print/format methods, `gptr_fork()`, `gptr_last()`, `gptr_sessions()` |
| `session-store.R` | L4 | JSONL v3 tree writer/reader, fork files, resume, crash-safe appends (builtin:store hooks) |
| `session-request.R` | L4 | transcript to request: render-once memo, cache anchors, operator entries, prefix guard |
| `session-compact.R` | L4 | threshold, checkpoint compactor (builtin:compaction), harness state extraction |
| `agent-loop.R` | L4 | run state machine, queues, max turns, budgets, retries, overflow, `gptr_step()` |
| `agent-dispatch.R` | L4 | argument validation, gate (policies + `tool_call` hooks), execution, results in source order |
| `agent-tools.R` | L4 | `gptr_tools` dispatcher object, exposure handling, R-signature catalog, nested-call gating |
| `prompt-sections.R` | L4 | section registry, presets, freeze, section patches (builtin sections registered here) |
| `prompt-context.R` | L4 | context blocks: project instructions, environment, mode, workspace, changes, attached, skill, plan |
| `prompt-templates.R` | L5 | prompt templates and slash-command expansion (builtin:prompts) |
| `eval-run.R` | L4 | hand-rolled evaluator: parse, capture, per-expression time limit, interrupts, state diff |
| `eval-plots.R` | L4 | plot capture hooks and replay to 768x512 PNG (ragg or png) |
| `eval-guard.R` | L4 | static guard (blocked calls) and interactive-function traps |
| `env-snapshot.R` | L4 | copy-safe snapshot (names, addresses, fingerprints), diff, task-callback log of user expressions |
| `env-describe.R` | L4 | `gptr_describe()` S3 generic and methods, workspace summary within budget |
| `tool-files.R` | L5 | read, write, edit tools and their R functions (byte-safe I/O, encodings, fuzzy fallback) |
| `tool-diff.R` | L5 | diff engine (prefix/suffix trim, patience anchors, Myers capped at D = 256) |
| `tool-search.R` | L5 | walker, gitignore engine, glob to PCRE, grep, find, ls (data-returning functions) |
| `tool-r.R` | L5 | the `r` tool definition (record, note, timeout), result formatting, `gptr_return()` |
| `tool-ask.R` | L5 | the `ask` tool and its UI mapping |
| `tool-glue.R` | L5 | polyglot helpers `run()`, `sh()`, `py()`, `sql()` exposed through `gptr_tools` |
| `perm-classify.R` | L5 | static R risk classifier (levels 0-4, categories, paths, secret rules) |
| `perm-policy.R` | L5 | builtin:permissions (modes, rules, prompt) and builtin:plan (scratch env, plan hand-off) |
| `skill-catalog.R` | L5 | skill discovery, compact catalog within budget, activation, `skills =` preload |
| `mcp-client.R` | L5 | MCP client: stdio and HTTP, both protocol eras, pagination, progress, cancel, OAuth hook |
| `mcp-config.R` | L5 | `mcp.json`, other-harness import, pure-R TOML subset, `gptr_mcp()` |
| `subagent-backends.R` | L5 | backends `inline`, `worker` (callr), `cli`; agent-file loader; `gptr_agent()` |
| `subagent-parallel.R` | L5 | `agents =`, `parallel =`, `gptr_parallel()`: parent session with children |
| `artifact-shiny.R` | L5 | artifact types `shiny` and `html`: snapshot, callr child, validation ladder, `gptr_artifacts()` |
| `doc-locate.R` | L5 | find the calling statement (srcref, source frame, knitr/Quarto, Rscript, IDE, console) |
| `doc-blocks.R` | L5 | block grammar, render and upsert, prompt hash, stale/edited detection |
| `doc-io.R` | L5 | atomic document I/O (EOL/BOM preserving, md5 check), deferred Rscript writes, IDE backends |
| `doc-formats.R` | L5 | doc formats `r`, `rmd`, `qmd`, `ipynb`, `transcript` (builtin:documents) |
| `doc-replay.R` | L5 | replay modes, S2 answer cache, `gptr_source()`, `gptr_cache()` |
| `console-repl.R` | L5 | REPL loop, line reader, input grammar (`!`, `!!`, `/cmd`, fences, `"""`), slash commands |
| `console-render.R` | L5 | chunk-invariant markdown stream renderer, tool lines, status line, verbosity |
| `console-interrupt.R` | L5 | interrupt policy: pause menu (steer, follow-up, continue, abort) via the resume restart |
| `console-ui.R` | L5 | UI backends: console, none, scripted, rstudio; `ctx$ui()` |
| `gptr-gateway.R` | L6 | `gptr()`: capture, prompt selection, identifier resolution, interpolation, routing |
| `gptr-config.R` | L6 | `gptr_init()`, `gptr_config()`, settings files (user, project, local), trust |
| `zzz.R` | - | `.onLoad` (register built-ins, lazy S3 registration for knitr/vctrs), `.onUnload` (stop children) |

### 3.2 `inst/`

```text
inst/COPYRIGHTS                      Pi (MIT: tool strings, error-pattern lists), models.dev (MIT),
                                     gitleaks-derived secret patterns (MIT), Codex handoff intent (none copied)
inst/extdata/models.json.gz          pruned models.dev snapshot + gptr overrides (about 50 KB) [09 §4]
inst/gptr/plugin.json                gptr's own manifest (built-ins are declared like any plugin)
inst/gptr/skills/high-performance-r/ SKILL.md + references [19 §3]
inst/gptr/skills/shiny-artifacts/    SKILL.md: Shiny/bslib house style for artifacts [17 §4.4, G4 §3.1]
inst/gptr/templates/vignette.Rmd     template written by gptr_init()
inst/gptr/prompts/review.md          example prompt template (/review)
inst/gptr/fixtures/fake_cli.R        fake claude/codex CLI used by tests and examples (no network)
```

### 3.3 Tests, shipped data, development assets

```text
tests/testthat.R
tests/testthat/setup.R               redirect R_USER_*_DIR, blank keys unless GPTR_LIVE_TESTS,
                                     options(gptr.interactive = FALSE, gptr.quiet = TRUE,
                                     gptr.replay = "replay"), OMP_THREAD_LIMIT = 2
tests/testthat/helper-fake.R         scripted fake-provider scenarios
tests/testthat/helper-mock-server.R  base-R SSE mock (serverSocket) run with callr; skip_on_cran
tests/testthat/fixtures/             anthropic/*.sse, openai/*.sse, completions/*.sse, gemini/*.sse,
                                     claude-cli/*.ndjson, codex/*.jsonl, jev/*.json, mcp/server.R (stdio,
                                     both eras), docs/*.R|Rmd|qmd|ipynb (round-trip), models-mini.json
tests/testthat/test-<area>-<topic>.R one per R file
tests/testthat/test-copy-safety.R    fresh-process tracemem suite (skip if !capabilities("profmem"))
tests/testthat/test-context-prefix.R 20-turn byte-prefix test [G4 §4.9]
tests/testthat/test-bench-context.R  static-prefix token budgets per preset (offline)
dev/bench/                           rtiktoken counts, cache simulation, north-star live runs (not shipped)
vignettes/                           precomputed (*.Rmd.orig -> *.Rmd): gptr, system-one, plugins, documents
```

---

## 4. Exported API

28 exported names, all `gptr` or `gptr_*` (D-28; no collisions [G1 §4.7]). `agent()` exists only
as an alias inside the `agents =` data mask. S3 methods are registered, not exported names.

| Tier | Names |
|---|---|
| Gateway | `gptr` |
| Setup and status | `gptr_init`, `gptr_config`, `gptr_env`, `gptr_providers`, `gptr_models`, `gptr_mcp` |
| Sessions (SDK) | `gptr_fork`, `gptr_step`, `gptr_on`, `gptr_parallel`, `gptr_sessions`, `gptr_last`, `gptr_usage` |
| Agent-side | `gptr_return`, `gptr_tools` (object), `gptr_describe` (S3 generic), `gptr_agent` |
| Documents and artifacts | `gptr_source`, `gptr_cache`, `gptr_artifacts` |
| Extension API | `gptr_register`, `gptr_spec`, `gptr_tool`, `gptr_registry`, `gptr_check`, `gptr_fake_provider`, `gptr_api` |

### 4.1 `gptr()`

```r
gptr = function(..., model = NULL, mode = NULL, tools = NULL, skills = NULL,
                extensions = NULL, plugins = NULL, agents = NULL, parallel = NULL,
                choices = NULL, levels = NULL, threshold = 0.5, min_confidence = 0,
                uncertain = NA, prompt = NULL, system = NULL, budget = NULL,
                envir = parent.frame(), .run = TRUE)
```

All formals follow `...`, so they match only by exact name (no partial-matching capture of context
arguments [05 §4]). Behaviour, in dispatch order:

**Step 1 — capture without forcing.** `dots = rlang::enquos(...)`; identifier formals (`model`,
`mode`, `tools`, `skills`, `extensions`, `plugins`, `agents`) are captured with `rlang::enquo()`.
rlang capture replaces base `substitute()` because forwarded dots resolved to the wrong frame with
base R, and because by-name inspection is what keeps large objects copy-free [12 §2.D2, P-A exp:
by-name `oldClass()`/`inherits()` checks leave no sticky reference].

**Step 2 — classify the dots.**

1. *Continuation.* If the first unnamed dot evaluates to a `gptr_session`, it is the session to
   continue. A symbol is checked by name (`oldClass(get(sym, envir))`); a call (the left side of a
   pipe such as `gptr("a") |> gptr("b")`) is evaluated once, which runs the earlier turn first
   (a non-session value of a call is kept as that context item, never evaluated twice). A
   `gptr_artifact` handle continues the session recorded in its `artifact.json` and attaches the
   artifact as context.
2. *Prompt.* `prompt =` if given; else the first unnamed string literal (a literal beats a value, so
   `abstract |> gptr("Is it an RCT?")` takes the literal); else the first unnamed dot whose value is a
   length-1 character vector (`gptr(task, ...)`). Programmatic mapping should name `prompt =`
   (`purrr::map` inlines constants) [12 §2.D3].
3. *Context.* Every other dot is an attached object, stored as a quosure with a label (the argument
   name, else the deparsed expression, so `mice |> gptr("...")` labels it `mice`).
4. *Interpolation.* `{name}` in the prompt is replaced when `name` is a syntactic R name bound in
   `envir` to an atomic vector of length 1..50 (values joined with ", "); `{{`/`}}` are literal
   braces; anything else (code, JSON, LaTeX with unbound names) is left as is. This makes north-star
   §11 (`"Cluster {cl} has ambiguous markers ({top})"`) work while leaving braces in code alone
   [P-A exp; 12 §2.D4 recommended no interpolation, overturned here only for this narrow rule,
   switchable with `options(gptr.interpolate = FALSE)`]. The document records the call as written
   (the template), not the interpolated text.

**Step 3 — resolve identifiers** (`model`, `mode`, `tools`, `skills`, `extensions`, `plugins`, and
names inside `agent()`), with this exact rule [12 §2.D1, §3.11]:

| Expression | Result |
|---|---|
| `NULL` | default from config |
| string literal `"opus"` | the string |
| symbol that is a **known name** (model alias, provider id, mode, tool, skill, plugin, agent) | the name, even if a variable of that name exists (as `library(pkg)` does) |
| `!!x` | the value of `x` (explicit escape for a variable shadowing a known name) |
| unknown symbol bound in the caller | its value if character (or a spec object for `tools`/`agents`); any other class is an error naming the class and suggesting quotes |
| unknown unbound symbol | the literal name (validated later against the catalog/registry, with `adist()` suggestions) |
| `c(a, "b")` | resolved element by element |
| other call (`if (hard) opus else haiku`) | evaluated in a mask that binds every known name to its string, parent = caller |

A resolved model that looks like a decimal version typed as a symbol (`gpt5.1`) is printed once, and
the document always records the quoted canonical id [09 §4.9].

**Step 4 — route.**

| Condition | Route | Returns |
|---|---|---|
| resolved `model` is a classifier provider (System 1) | `s1_call()`: states from the context (and `as_state(session)` if a session was piped in); `choices` gives a choice, `levels` a score, neither a decision | `gptr_decision` / `gptr_choice` / `gptr_score` (never a session) |
| no prompt, no session, no context | interactive console if a human is present (`gptr_has_human()`), else `gptr_error_noninteractive` | the session, invisibly, on `/exit` |
| no prompt, with a session and/or context | console continuing that session with the context attached (human present); else error | the session, invisibly |
| `agents =` given | parent session; one child per agent definition, run concurrently (section 6.12) | parent session (children reachable as `res$<name>`) |
| `parallel = n` and one list-like context object | parent session; one child per element, at most `n` active | parent session (children named by element names) |
| continuation session is `running` (a hook, sibling agent or nested call pipes into it) | enqueue a steering message, delivered after the current tool-result message | the session, invisibly, without running |
| otherwise | new or continued session; append a user entry (attached-context blocks, workspace diff, mode/model change operator entries); run the loop unless `.run = FALSE` | the session (invisibly if the answer was streamed to the console, visibly otherwise) |

After a run, the session is `the$last`. On interrupt in programmatic use, the partial turn is
persisted, the session stays reachable with `gptr_last()`, and the interrupt is re-signalled so
loops stop [15 §4.7]. Provider failures after retries give `status = "error"` and a classed
condition `gptr_error_provider` (the session is attached to the condition as `cnd$session`).

Other arguments: `tools` accepts names (bare or quoted), `"+grep"`/`"-write"` modifiers, a preset
(`"minimal"`, `"lean"`, `"full"`) or `gptr_tool()` specs (rank 0). `skills` preloads skill bodies as
`<skill_content>` blocks. `extensions` accepts factories (`function(gptr)`) or file paths;
`plugins` accepts plugin names (installed packages with `inst/gptr/` or directories); both are
session-scoped (rank 0) and lazily activated. `system` replaces the preamble/tools/rules sections
(a string) or overrides named sections (a named list; `NULL` removes). `budget = list(tokens =,
cost =, turns =)` stops the run at a turn boundary with `status = "budget"`. `envir` is where the
`r` tool evaluates (default: the caller's frame; a magrittr mask is detected and replaced by its
parent [12 §2.B4]). `.run = FALSE` returns the session with the prompt queued (SDK).

### 4.2 Setup and status

```r
gptr_init(path, instructions = TRUE, record = TRUE)
```
Creates `path/.gptr/` with `vignette.Rmd` (from the template), `settings.json` (`record`
consent), `.gitignore` (`sessions/`, `cache/s2/`, `cache/tmp/`, `artifacts/*/snapshot/`, locks) and,
in a package project, appends `^\.gptr$` to `.Rbuildignore`. `path` has no default: when missing,
an interactive session asks "Create .gptr/ in <getwd()>?"; a non-interactive call errors. The
directory marks the project as trusted by the user who created it. Returns the path invisibly
[13 §2, 14 §3.7]. This makes north-star §9's `gptr_init()` work at the console.

```r
gptr_config(..., scope = c("session", "project", "user"))
```
With no arguments returns the effective configuration (class `gptr_config`, printed with the source
of each value). With named arguments sets keys in the scope: `model`, `mode`, `tools`, `preset`,
`system1`, `record`, `replay`, `context` (`"summary"`, `"names"`, `"none"`), `budget`, `max_turns`,
`permissions = list(allow, ask, deny)`, `plugins`, `filters`, `trust`, `document`, `cache_commit`.
Identifiers use the same NSE rule (`gptr_config(model = sonnet, mode = manual)`). Project scope may
only tighten security settings (mode order plan > manual > edits > auto; project filters cannot
disable user or built-in policies) [18 §4.7, G1 §3.6].

```r
gptr_env(path = ".env", aliases = NULL, set_env = TRUE)
```
Parses a `.env` file with gptr's own parser (BOM, CRLF, `export`, quotes, inline comments,
hyphenated names), maps aliases (`jev-key`, `JEV_KEY`, `JEV_API_KEY`, `TYPESAFE_KEY` to
`TYPESAFE_API_KEY`; a canonical spelling wins over an alias), registers every value in the vault and
optionally exports canonical names. Returns a report of names and fingerprints only [G6 §1.2, 04a].

```r
gptr_providers(check = FALSE)
```
Data frame: provider id, type (chat, classifier, cli), api, credential (name + fingerprint, never a
value), status (key found, CLI found and version, logged in), default model. `check = TRUE` performs
cheap reachability checks (models endpoint with a 2 s timeout; `claude auth status --json` keeping
only loggedIn/authMethod/subscriptionType [07 §4]). Never called on load or in examples.

```r
gptr_models(query = NULL, provider = NULL, refresh = FALSE)
```
Searches the merged catalog (snapshot < cache < overrides < user config < live discovery for local
servers). `refresh = TRUE` updates the models.dev cache with ETag into
`tools::R_user_dir("gptr", "cache")` [09 §4].

```r
gptr_mcp(server = NULL, import = FALSE, login = NULL, refresh = FALSE)
```
Lists configured MCP servers (own `mcp.json` at user and trusted-project level, plus imported
Claude Code, Codex, Cursor, VS Code, Claude Desktop configs) with status, era and tool counts.
`import = TRUE` copies user-level configs of other harnesses into gptr's user `mcp.json` (never
writes theirs). `login = "<server>"` runs the OAuth flow. `refresh = TRUE` reconnects and refreshes
the tool cache.

### 4.3 Sessions (SDK)

```r
gptr_fork(session, isolate = FALSE)
```
New session with a copy of the transcript entries (immutable lists, no deep copy), a new id, a new
JSONL file whose header names the parent (Pi v3 `parentSession`), and none of the parent's listeners,
queues, connections or children (INFRA-14). `isolate = TRUE` evaluates the fork's `r` code in
`new.env(parent = session$envir)` so its objects stay in `fork$objects` instead of the workspace.

```r
gptr_step(session, turns = 1L)
```
Runs up to `turns` model turns (each turn includes its tool calls) of a session created with
`.run = FALSE` or left with queued follow-ups; `turns = Inf` runs to settlement. Returns the session.

```r
gptr_on(session, event, handler, matcher = NULL)
```
Session-scoped hook (rank 0). `handler(event, ctx)` follows the event's dispatch semantics (section
6.3). Returns a zero-argument function that removes the hook. Listeners are never copied by
`gptr_fork()`.

```r
gptr_parallel(..., .max_active = getOption("gptr.max_active", 8L))
```
Each argument is a `gptr()` call (forced under a dynamic flag so that it returns an unstarted
session) or a session created with `.run = FALSE`; all run concurrently in one reactor. Returns a parent session whose children
are named by the argument names (`res$plan`, `res$lit`).

```r
gptr_sessions(id = NULL, all = FALSE)
```
Without `id`: data frame of stored sessions of the workspace (or of the temp store); `all = TRUE`
adds sessions of other projects in `R_user_dir("gptr", "data")` (only when that store was consented
to). With `id`: resumes that session from its JSONL file (leaf = last entry) and returns it.

```r
gptr_last()
```
The most recently active session, including one whose call was interrupted before assignment.

```r
gptr_usage(x = NULL, by = c("model", "route", "agent"))
```
Usage and cost of a session, a list of sessions, or (NULL) all sessions stored in the workspace today.
Includes children. Class `gptr_usage` (data frame of request records plus totals).

### 4.4 Agent-side functions

```r
gptr_return(x)
```
Called by agent code inside the `r` tool: designates `x` as the session's `$value`. Errors outside a
running `r` evaluation. The object is shared (not copied) with `envir`.

```r
gptr_tools    # exported object of class "gptr_tools"
```
The dispatcher that makes every capability an R function (REQ-42 composition). `gptr_tools$grep(...)`,
`gptr_tools$find(...)`, `gptr_tools$ls(...)`, `gptr_tools$read(...)`, `gptr_tools$run(...)`,
`gptr_tools$sh(...)`, `gptr_tools$py(...)`, `gptr_tools$sql(...)`, `gptr_tools$artifact(...)`, plugin
tools `gptr_tools$<name>(...)`, MCP tools `gptr_tools$<server>$<tool>(...)`, plus reserved helpers
`gptr_tools$search("words")` (BM25 over names and descriptions) and `gptr_tools$help("<name>")` (full
schema). Resolution is lazy against the running session's registry (or the process registry at the
console). Calls made while an `r` evaluation runs pass through the same gate and hooks as
model-issued tool calls (nested gating, section 6.4) and return R values, not text. The name avoids
the base `tools` package [06 open question, G1 §4.7].

```r
gptr_describe(x, budget = 300L, ...)
```
S3 generic used for attached objects and workspace summaries; returns character lines, first line a
header `<class> shape, size`, at most `budget` tokens; methods must not force promises or do I/O
[12 §3.9]. Plugins register methods with delayed `S3method(gptr::gptr_describe, cls)`.

```r
gptr_agent(name = NULL, model = NULL, skills = NULL, tools = NULL, system = NULL,
           backend = c("inline", "worker", "cli"), objects = NULL, export = NULL,
           mode = NULL, max_turns = NULL)
```
Agent definition (spec kind `agent`). With only `name`, loads the definition from agent files
(`.gptr/agents`, `.claude/agents`, `.pi/agents`, user level). `model` and `skills` use the gateway's
NSE rule. Inside `gptr(agents = list(...))`, `agent()` is bound to this function in a data mask, so
the north-star spelling works without exporting `agent` [15 §4.3].

### 4.5 Documents and artifacts

```r
gptr_source(file, replay = getOption("gptr.replay", "auto"), envir = parent.frame(), echo = FALSE)
```
Sources a script with replay awareness: fresh blocks run as recorded code; in `live`/`record` mode
stale blocks are regenerated and the old block's top-level expressions are skipped, which base
`source()` cannot do [14 §4.4].

```r
gptr_cache(action = c("info", "prune", "clear"), kind = c("all", "s1", "s2"))
```
Reports, prunes (entries of deleted blocks; S1 entries unused for 90 days; `cache/tmp` older than 7
days) or clears the workspace caches ("actively managed" [17 §3.5, 13]).

```r
gptr_artifacts(id = NULL, open = FALSE, stop = FALSE)
```
Without `id`: data frame of artifacts (id, title, version, status, url, data snapshot sizes). With
`id`: returns a `gptr_artifact` handle (print shows url and path), opening it in the viewer
(`open = TRUE`) or stopping its process (`stop = TRUE`). A handle piped into `gptr()` continues the
session that built it with the artifact attached.

### 4.6 Extension API

```r
gptr_spec(kind, name, ...)
gptr_tool(name, description, parameters, execute, exposure = c("r", "direct", "hidden"),
          execution = c("sequential", "concurrent"), risk = NULL, snippet = NULL,
          guidelines = NULL, signature = NULL)
gptr_register(spec, rank = c("user", "session"))
gptr_registry(kind = NULL, diagnostics = FALSE)
gptr_check(x, error = FALSE)
gptr_fake_provider(script, name = "fake")
gptr_api()
```
`gptr_spec()` constructs a spec of any of the 19 kinds (section 13) and validates it with the kind's
validator; `gptr_tool()` is the sugar for the most common kind. `gptr_register()` registers at top
level (process lifetime) and returns an unregister function; inside a factory the same verb is
`api$register(spec)`. `gptr_registry()` lists records with kind, name, source, rank, enabled and an
estimated `tokens` column. `gptr_check()` runs the conformance suite for a spec, factory or package
(section 13.3). `gptr_fake_provider()` registers a scripted provider (script = list of replies or a
function of the request) and returns its model id; every example in the manual uses it, so examples
run offline on CRAN. `gptr_api()` returns `list(version = package_version("1.0"), features =
character())`.

---

## 5. Core data structures

Mutable things are environments with an S3 class; immutable things are classed lists or base-typed
S3 vectors (D-02) [G1 §4.3]. JSON field names on disk are Pi-compatible camelCase; R fields are
snake_case (mapping table in `provider-messages.R`, [03 §4.2]).

### 5.1 Session (`gptr_session`, environment, reference semantics per S-8)

| Field | Type | Meaning |
|---|---|---|
| `id` | chr | `"s"` + 12 hex (RNG-free) |
| `parent_id`, `fork_of` | chr/NULL | parent (sub-agent) or fork source |
| `depth` | int | 0 top level, +1 per nesting |
| `created` | POSIXct | |
| `envir` | environment | where `r` evaluates (reference to the user's environment, never to objects) |
| `model` | chr | resolved `provider/id[:thinking]` of the next request |
| `mode` | chr | `plan`, `manual`, `edits`, `auto` |
| `preset` | chr | `minimal`, `lean`, `full` |
| `tools` | chr | frozen direct tool names; the R-function catalog is frozen with the system prompt |
| `system` | list | frozen `list(t0 = <chr>, t1 = <chr>, sections = <names>)` |
| `entries` | list | transcript entries (append-only; section 5.2) |
| `store` | env/NULL | open JSONL store (path, connection, leaf id) |
| `doc` | list/NULL | recording target (path, format, block ids per call) |
| `status` | chr | `idle`, `running`, `done`, `error`, `aborted`, `blocked`, `budget`, `max_turns` |
| `queue` | list | `steer` and `follow_up` lists of pending user texts |
| `text` | chr | last assistant text |
| `value`, `has_value` | any, lgl | value designated by `gptr_return()` |
| `usage` | `gptr_usage` | request records and totals, children included |
| `children` | named list | child sessions (sub-agents, parallel fan-out) |
| `listeners` | list | session-scoped hooks |
| `snapshot` | data.frame | last workspace snapshot (names, addresses, fingerprints; no values) |
| `budget`, `turns` | list, int | limits and counter |
| `views` | env | last request element view per `(provider, model)` for the prefix guard |
| `ext_state` | env | per-plugin, per-session state (`ctx$state()`) |
| `backend` | chr | `inline` (default), `worker`, `cli` for children |
| `objects` | env/NULL | overlay environment of an isolated fork or inline sub-agent |

Methods: `$` returns public fields (`text`, `value`, `usage`, `model`, `mode`, `status`, `id`,
`turns`, `history`, `children`) and falls through to a child by name (`reviews$stats`); `$<-` allows
only `value` (the replay line `res$value = fit` [14 §4.4.6]); `[[` indexes children; `print` shows the
last answer and a footer `<gptr_session s1a2b3c4d5e6 | 3 turns | anthropic/claude-sonnet-5-5 |
4,812 tokens $0.021 | value: <lm>>`; `format`/`as.character` give the text; `knit_print` (registered
lazily) emits Markdown. `$history` returns the projected messages as a `gptr_history` list.

### 5.2 Transcript entries, messages and content blocks (INFRA-07)

Entries are classed lists with common fields `id`, `parent_id`, `ts`, `type`:

| `type` | Fields |
|---|---|
| `user` | `blocks` (context and prompt blocks, in order), `source` (`prompt`, `pipe`, `follow_up`, `repl`, `parent`) |
| `assistant` | `blocks`, `api`, `provider`, `model`, `response_id`, `usage` (5.5), `stop_reason` (`stop`, `length`, `tool_use`, `aborted`, `error`, `refusal`), `error_message`, `raw_items` (provider opaque items kept byte-exact) |
| `tool_results` | `results` (list of 5.3 results, source order) |
| `operator` | `kind` (`steer_relay`, `mode`, `model`, `section_patch`, `tool_change`, `plan`), `text`, `tool_add` |
| `compaction` | `blocks` (new first message), `summary`, `state`, `tokens_before`, `first_kept` |
| `custom` | `custom_type` (`gptr.doc_block`, `gptr.replay`, `gptr.decision`, ...), `data` |

Content blocks:

```r
list(type = "text", text = "...", signature = NULL)
list(type = "thinking", text = "...", signature = "<opaque>", redacted = FALSE, data = NULL,
     origin = list(api = "anthropic-messages", provider = "anthropic", model = "claude-sonnet-5-5"))
list(type = "image", media_type = "image/png", data = "<base64 without newlines>",
     source = "plot", width = 768L, height = 512L)          # source: plot, file or screenshot
list(type = "tool_call", id = "toolu_...", name = "r", arguments = list(), raw = "<json>",
     provider_ids = list(call_id = "call_...", item_id = "fc_..."), thought_signature = NULL)
list(type = "context", kind = "workspace", attrs = list(), text = "...", anchor = FALSE)
# context kinds: project_instructions, environment, mode, workspace, workspace_changes,
#   attached, skill, plan, checkpoint, prompt
```

Projection before every request (never an edit of stored entries): drop `aborted`/`error`
assistant entries, add a synthetic result "interrupted after 2.3 s; side effects may have occurred"
or "No result provided" for orphaned calls, place steering relays after complete tool-result
entries, and apply the hand-off transform for the target model (same model: keep signatures and
opaque items; otherwise thinking becomes text or is dropped by policy, opaque data dropped, ids
normalised) [10a INFRA-04/08, 02 §2.7].

### 5.3 Tool definition and tool result

```r
# spec of kind "tool" (gptr_tool())
list(kind = "tool", name = "grep", description = "...", parameters = <JSON Schema as list>,
     execute = function(input, ctx) ..., exposure = "r", execution = "sequential",
     risk = function(input, ctx) list(level = 0L, categories = character(), paths = character()),
     snippet = "Search file contents", guidelines = character(),
     signature = "grep(pattern, path = \".\", glob = NULL, limit = 100)  # data frame of matches",
     annotations = list(readOnlyHint = TRUE), replay_safe = TRUE, api = "1.0")

# result (class gptr_tool_result)
list(tool_call_id = "toolu_1", tool_name = "r",
     content = list(list(type = "text", text = "..."), list(type = "image", ...)),
     is_error = FALSE,
     details = list(value = NULL, code = "...", record = TRUE, note = NULL, status = "ok",
                    objects = list(added = "fit", modified = character(), removed = character()),
                    diff = NULL, spill = NULL, elapsed = 0.42, nested = list()),
     usage = NULL)          # set for sub-agent tools
```

`execute` may return a character vector (text), a `gptr_tool_result`, or a list with `text`,
`images`, `value`, `is_error`; the dispatcher normalises it. Only `content` and `is_error` reach the
model; `details` feed the console, the document writer and `$value` [01 §2.1].

### 5.4 Events

`list(type = <event>, session = <id>, run = <id>, ts = <POSIXct>, ...)`; `message_update` is
delta-only (`block_index`, `delta`), never the partial message (quadratic copies [02 §4.4, 19 §2.4]).
Provider-level events (INFRA-02): `start`, `text_start|delta|end`, `thinking_start|delta|end`,
`toolcall_start|delta|end`, `done(reason)`, `error(reason, partial)`. Agent-level events are the hook
catalogue of section 6.3.

### 5.5 Usage and cost

```r
# one row per request in session$usage$requests
data.frame(session, agent, provider, model, route, input, output, cache_read,
           cache_write_5m, cache_write_1h, reasoning, cost, estimated, request_id, ts)
# route: "api", "plan-cli", "system-one", "emulated"; estimated = TRUE when no provider usage
```

Cost uses catalog prices per million tokens with context tiers and TTL-split cache writes (1 h
writes at 2x input) [03 §2.7, 10a INFRA-20]; CLI routes report the CLI's own figures marked as plan
estimates. Totals roll up children.

### 5.6 System 1 typed vectors [04 §4.5]

| Class | Base type | Attributes |
|---|---|---|
| `c("gptr_decision", "gptr_s1")` | logical | `names`, `prob` (P(yes)), `threshold`, `meta` |
| `c("gptr_choice", "gptr_s1")` | character | `names`, `s1_levels` (options in request order), `probabilities` (matrix n x k), `confidence`, `meta` |
| `c("gptr_score", "gptr_s1")` | double (expected 0-based level) | `names`, `s1_levels`, `probabilities`, `confidence`, `meta` |

`meta = list(model = "jev-1.13.0", engine = "typesafe", calibrated = TRUE, date, usage,
request_ids, errors)` (engine `emulated:structured` and `calibrated = FALSE` for emulation). Methods: `[`, `[[`, `[<-`, `c`, `rep`, `format` (`TRUE (p=0.93)`),
`print`, `as.data.frame`, `as.logical`/`as.character`/`as.double`, and `Ops`/`Math`/`Summary` group
methods that return bare vectors; vctrs proxy/restore methods registered when vctrs is loaded. The
options attribute is never called `levels` [04 §2.15]. A choice whose option spells "TRUE"/"T"/
"true" is rejected at request time because `if()` would accept it [04 verification].

### 5.7 Artifacts [17 §4]

```text
<root>/artifacts/<id>/artifact.json    {id, title, kind, version, session, created, updated, data: [{name, class, dim, bytes}]}
<root>/artifacts/<id>/vNNN/app.R       + R/gptr_data.R + data/<name>.rds (snapshot, uncompressed)
<root>/artifacts/<id>/run/             run.json {pid, port, url, version, started}, port, app-vNNN.log
```
`<root>` is `.gptr` in a consented workspace, else `tempdir()/gptr`. Handle class `gptr_artifact`:
`list(id, title, version, url, path, status, session)`.

### 5.8 Sub-agent handles

Every child is a `gptr_session` with `backend` set. For `worker` and `cli` children the session is a
proxy: its entries are rebuilt from the child's JSONL events, `envir` is `NULL`, and a private
`proc` field holds the processx/callr object; `cancel` interrupts then kills the tree after a 5 s
grace (checking `is_alive()`, not Pi's `killed` flag [06 verification]).

### 5.9 Settings

JSON files read with `simplifyVector = FALSE`, written by top-level field through temp + rename:
`R_user_dir("gptr","config")/settings.json` (user), `.gptr/settings.json` (project, trust-gated, may
only tighten), `.gptr/settings.local.json` (personal remembered permissions, gitignored).

```json
{"version": 1, "model": "anthropic/claude-sonnet-5-5", "mode": "manual", "preset": "lean",
 "tools": ["read", "write", "edit", "r"], "system1": "typesafe/jev-latest", "context": "summary",
 "record": "auto", "replay": "auto", "transcript": "ask", "cache_commit": false,
 "max_turns": 50, "budget": {"tokens": null, "cost": null},
 "permissions": {"allow": ["write(results/**)"], "ask": [], "deny": ["r(fn:install.packages)"]},
 "plugins": [], "filters": [], "compact_at": 200000}
```

---

## 6. Key internal interfaces

All internal functions are unexported, carry `@noRd`, and never throw into the loop unless stated.

### 6.1 Provider adapter contract (spec kind `adapter`) [G1 §3.1 row 2, 10a INFRA-02/17]

```r
gptr_spec("adapter", "anthropic-messages",
  transport = "http_sse",            # "http_sse" | "http_ndjson" | "http_json" | "process_jsonl" | "inprocess"
  build = function(model, req, opts) {
    # model: catalog record; req: list(system = list(t0, t1), tools = <frozen tool list>,
    #   entries = <projected transcript>, params = list(max_tokens, thinking, effort), ttl)
    # returns list(url, method = "POST", headers = list(... gptr_secret handles ...),
    #   body = <raw, assembled by concatenation of memoised entry JSON>, view = <element summary>,
    #   first_byte_timeout = 120, idle_timeout = 90, connect_timeout = 20)
  },
  decoder = function(model, opts) {
    # returns list(push = function(event, data), finish = function(), fail = function(cnd))
    # emits INFRA-02 events through opts$emit(); on finish/fail returns the assistant entry
    # (stop_reason, usage, raw opaque items); never signals an R condition
  },
  classify = NULL,                    # classifier adapters: list(build, parse), section 6.14
  caps = list(images_in_results = TRUE, operator_role = "system", cache = "anthropic",
              tool_addition = TRUE, max_tool_name = 128L))
```

`process_jsonl` adapters return `list(command, args, stdin = <raw>, env_profile, cwd)` from `build`
and receive lines in `push`. An `inprocess` adapter (for exotic plugins) provides
`stream(model, req, opts)` that must poll `opts$signal` and return within `opts$deadline`. Providers
are data records bound to an adapter by `api` (id, base_url, auth resolver, headers, compat, models);
an OpenAI-compatible host is added with data only (INFRA-17). Every adapter passes the conformance
suite: golden event sequence per fixture, one `error` event carrying the partial on a server error or
a truncated connection, split-UTF-8 chunk invariance, byte-identical re-serialisation of opaque
fields (INFRA-07/23/24).

### 6.2 Reactor (`http-reactor.R`) [15 §4.2, 10a INFRA-01/05/06/16/21]

```r
r = reactor_new(max_active = 8L, host_con = 100L)
id = reactor_http(r, spec, on_data = function(raw) NULL, on_headers = function(status, headers) NULL,
                  on_done = function(status, headers) NULL, on_fail = function(cnd) NULL,
                  provider = "anthropic")
id = reactor_proc(r, proc, on_line = function(line) NULL, on_exit = function(status) NULL)
reactor_timer(r, delay_s, fn)
reactor_run(r, until = function() FALSE, slice_ms = 100L)
reactor_cancel(r, id)
reactor_close(r)    # multi_cancel all; interrupt procs; poll up to 5 s; kill_tree the alive ones
```

Loop: admit queued transfers while global and per-provider slots allow; if the tool FIFO is non-empty
run exactly one tool, then drain the network with `curl::multi_run(timeout = 0)`; else
`processx::poll(c(processx::curl_fds(curl::multi_fdset(pool)), live procs), ms = min(next timer,
slice))`, `multi_run(timeout = 0)`, read ready pipes, fire due timers. Every handle sets
`pipewait = 0L`, `connecttimeout`, `low_speed_limit`/`low_speed_time`; the reactor enforces the
first-byte and idle timers itself; there is no total timeout on streams. Retry policy per transfer
(before any delta is committed): 408, 409, 429, 5xx, 529 and network errors; honour
`retry-after-ms` then `retry-after`, capped by `max_retry_delay = 60` (fail fast above it, stating the
server's delay); otherwise `0.5 s * 2^i` with time-derived jitter (no RNG), cap 8 s, at most 4
attempts; never retry Anthropic's spend-cap 429 (`enforced_spend_limit_reached`) [07 §4]. Rate-limit
headers (`anthropic-ratelimit-*`, `x-ratelimit-*`) feed a per-provider token bucket that gates
admission. The reactor is created per top-level `gptr()` call inside `on.exit(reactor_close(r))`.

### 6.3 Event bus and hooks (`ext-hooks.R`) — D-25

Canonical names are Pi-derived where the semantics match; gptr-specific events are added; Claude and
Codex names are accepted only by the (v1.x) hook importer's alias map, and `gptr_on(s,
"PreToolUse", ...)` fails with "did you mean 'tool_call'?" [G1 §3.2].

| Event | Semantics | Payload (besides type, session, run, ts) | Handler may return |
|---|---|---|---|
| `session_start` | collect, before the system prompt freezes | `session` | `list(sections, blocks)` |
| `session_end` | notify | `reason` | - |
| `input` | transform chain | `text`, `source` | `list(action = "continue" \| "transform" \| "handled", text)` |
| `turn_start` / `turn_end` | notify | `turn` / `turn, message, results` | - |
| `before_request` | notify, read-only | `provider, model, view, tokens_est` | - |
| `message_update` | notify, delta-only | `block_index, kind, delta` | - |
| `message_end` | notify | `entry` | - |
| `tool_call` | decision, **error = deny** | `tool, input, risk, nested, outer_level` | `list(decision, reason, input)` |
| `permission_request` | first decision, **error = deny** | `tool, input, risk, reason` | `list(decision = "allow" \| "deny", reason)` |
| `tool_result` | patch chain | `tool, input, content, details, is_error` | `list(content, details, is_error)` |
| `agent_end` | notify | `status, usage` | - |
| `pre_compact` / `post_compact` | first decision / notify | `reason, tokens` / `summary_tokens` | `list(cancel, result)` / - |
| `document_write` | block + patch, **error = block** | `path, format, block, lines` | `list(block, reason)` or `list(lines)` |
| `decision` | notify | `model, question, n, summary` | - |
| `subagent_start` / `subagent_end` | notify | `child, backend, model` / `+ status, usage` | - |
| `artifact_start` / `artifact_stop` | notify | `id, url, version` | - |
| `cache_break` | notify | `provider, model, first_diff, culprit` | - |
| `budget_exceeded` | notify | `usage, budget` | - |
| `error` | notify | `provider, status, retry` | - |

Dispatch: records are indexed by event (dispatch cost does not grow with unrelated hooks [G1 risk]);
rank order (session 0, project 1, user 3, plugin 5, built-in 6); errors in notify/patch handlers are
diagnostics (`gptr_registry(diagnostics = TRUE)`), errors in fail-closed events deny. Patch returns,
never mutation, because R lists have value semantics [05 §4]. Hook-injected context is capped at
10,000 characters [20 §3.7]. `transform_context`-style rewriting of earlier entries is not offered in
v1 (it would break the append-only prefix); plugins add context through `context` blocks instead.

### 6.4 Agent loop and tool dispatcher (`agent-loop.R`, `agent-dispatch.R`) [02 §2.2, 10a INFRA-09/10/12]

```r
run = run_new(session, entries, reactor, opts)   # opts: max_turns, budget, interactive, depth
run_step(run)                                     # advance one transition; returns run$state
run_settle(runs, reactor)                         # drive runs until each is terminal
dispatch_tools(run, calls, ctx)                   # -> list of gptr_tool_result, source order
tool_validate(schema, input)                      # -> list(ok, input, error); explicit coercion only
tool_gate(call, tool, input, risk, ctx)           # -> list(decision, reason, input)
tool_execute(tool, input, ctx)                    # never throws (errors, warn = 2, timeout, interrupt)
```

States: `queued -> requesting -> streaming -> tools -> check_queues -> (requesting | done)`, plus
`waiting_user`, `waiting_children`, and terminal `done`, `error`, `aborted`, `blocked`, `budget`,
`max_turns`. Steering is drained at run start, after each complete tool-result entry and before
each request; follow-ups are drained when the run would otherwise stop. `max_turns` defaults to 50
(`gptr.max_turns`); budgets are checked at turn boundaries. A response stopped for `length` or
`refusal` never executes its tool calls (each gets an error result). Overflow (24 error patterns or
usage) triggers one compact-and-retry; agent-level retry of a mid-stream error after committed
deltas: at most 2 retries at 2 s and 4 s [02 §2.8, 10a INFRA-06].

Nested gating. A `gptr_tools$x()` call made while an `r` evaluation runs enters
`dispatch_nested(tool, input, ctx)`: if the static analysis of the outer code listed the same
function and its risk level is at most the level the user approved for the outer call, it runs
without a second prompt; otherwise it goes through `tool_gate()`. The nested call is recorded in the
outer result's `details$nested` (bounded to 20 entries) [06 §4].

### 6.5 Evaluator (`eval-run.R`, `eval-plots.R`, `eval-guard.R`) [12 §3, §4.3]

```r
eval_r(code, envir, timeout = 300, plots = c("auto", "capture", "none"), tee = interactive(),
       max_chars = 20000L, max_lines = 800L)
# -> gptr_eval_result: status (ok | error | timeout | interrupt | blocked | parse_error), events,
#    n_done, n_total, changes (wd, options, env var names, packages, devices, connections),
#    elapsed, images, spill
format_eval_result(res, max_chars)
```

Hand-rolled, not `evaluate` (sink breakage, sticky references, options leak [12 §2.A2]): parse with
`srcfilecopy()`, static guard, `sink()` capture cleaned up in `suspendInterrupts()`, per-expression
`setTimeLimit(elapsed, transient = TRUE)` reset to `Inf`, symbols printed by name and assignments
evaluated without `withVisible()`, interrupts caught per expression (resume restart) and around the
loop, plots replayed to 768x512 PNG (532 tokens). The value of an evaluation is never kept [12 §4.3].

### 6.6 Environment snapshot, diff and describe (`env-snapshot.R`, `env-describe.R`) [12 §3.8, 21 §2.9]

```r
env_snapshot(envir)          # data.frame(name, kind, address, class, bytes, shape, fp); no values
env_diff(old, new)           # list(added, removed, modified)
user_expr_log(session)       # addTaskCallback() log of the user's top-level expressions (last 20)
workspace_block(envir, snapshot, budget = 600L)
```

Fingerprint = address + type + length + attribute addresses + 64 sampled values; full `rlang::hash()`
only up to 50 MB. In-place edits of big objects at unsampled positions are caught by static analysis
of evaluated code (assignment targets, replacement calls, `:=`, `set*()`) and the user-expression
log. No binding locks: `lockBinding()`/`unlockBinding()` makes the next in-place edit copy the whole
object (1 copy vs 0, fresh processes), while address snapshots from function frames leave no
reference [P-A exp].

### 6.7 Permission policy (spec kind `policy`, `perm-policy.R`) [18 §3.7-3.8, §4.7; G6 §3.8]

```r
gptr_spec("policy", "builtin:permissions",
  check = function(call, ctx) {
    # call: list(tool, input, risk = list(level, categories, flagged, paths, secret),
    #            nested, outer_level)
    # -> NULL | list(decision = "allow" | "deny" | "ask" | "modify", reason, input)
  })
```

Combination: deny > ask > modify > allow; a throwing policy denies; project settings cannot disable a
user or built-in policy. Mode table (18 §4.7) plus: overwriting an object larger than
`gptr.protect_size` (100 MB) is level 3; secret access is level 3 with a guard that asks even in
`auto`; secret source plus network sink is level 4 [G6 §3.8]. `ask` with a human: the UI prompt
(yes / yes this session for `<rule>` / always in this project / no with feedback / no; Ctrl-C
aborts). `ask` without a human: the run stops with `status = "blocked"` and a classed
`gptr_error_permission` that states the action and how to allow it (north-star §12);
`options(gptr.noninteractive_ask = "deny")` instead returns a denial to the model.

### 6.8 Document writer (spec kind `doc_format`, `doc-*.R`) [14 §3-4]

```r
gptr_spec("doc_format", "r", ext = c("R", "r"),
  locate = function(call, prompt, calls) NULL,    # -> location(kind, path, stmt, ordinal, backend)
  render = function(block) character(),           # block: id, header, code, outputs, notes
  write  = function(location, block, mode) NULL)  # atomic, md5-checked, EOL/BOM-preserving
```

`builtin:documents` listens to `agent_end` of runs started by a top-level call (not nested in a
function, loop, `if` or braces, not inside an agent block), renders 14's block grammar (`# >>>
gptr:<id> model= date= prompt= [sha= call= tokens= cost= session= value= fork=]` ... `# <<<
gptr:<id>`) and emits `document_write` (fail closed) before writing. Rscript writes are deferred to
`reg.finalizer(onexit = TRUE)` with a crash sidecar; IDE buffers go through rstudioapi; open
notebooks are never written [14 §4.3]. Top-level System 1 calls get a one-line block (`#>
gptr_decision: 14 TRUE / 6 FALSE (jev-1.13.0, 2026-09-29)`); System 1 calls in control flow write
nothing.

### 6.9 Session store (`session-store.R`) [02 §4, 10a INFRA-13]

```r
store_open(session, dir)        # .gptr/sessions/<YYYYmmddTHHMMSS>_<id>.jsonl or tempdir()/gptr/sessions
store_append(store, entry)      # kept-open file(path, "ab"); one line; flush; suspendInterrupts()
store_read(path)                # tolerant of a truncated last line
store_fork(store, leaf, dest)   # new file whose header names parentSession
```

Header `{"type":"session","version":3,"id","timestamp","cwd","parentSession","gptr":{"version",
"api"}}`; entries in Pi v3 shapes (`message`, `model_change`, `compaction`, `custom`) with
`id`/`parentId`, so the file is a tree although v1 appends to one leaf per session. Secrets are
redacted at ingress, so the file is never rewritten [G6 §1].

### 6.10 Request assembly and caching (`session-request.R`) [G4 §2.7, §3.7, §4.2-4.3]

```r
build_request(session, target, extra_tail = NULL)   # -> list(body, view, tokens_est)
entry_json(entry, api, same_model)                  # memoised per (entry id, api, same_model, caps)
prefix_guard(session, target, view)                 # emits cache_break with the first differing element
```

Seven rules adopted from G4: freeze the tools array and system prompt; tier T0 before T1; render each
entry once; append, never edit; authority by role (operator messages only for harness facts);
two 1 h anchors (end of T0, end of the project block) plus automatic tail caching (tail TTL 5 min,
switched to 1 h when interactive, when a tool took over 60 s, or when an object over 1 GB is in the
workspace); prefix guard. Per-provider shapes follow G4 §3.7.

### 6.11 MCP client (`mcp-client.R`) [16 §4, 06 §4]

```r
mcp_connect(spec, reactor = NULL)     # -> conn env: era ("2025-11-25" | "2026-07-28"), caps, tools
mcp_list_tools(conn, refresh = FALSE) # paginated; cached per config hash
mcp_call(conn, name, args, timeout = 60, on_progress = NULL)   # -> list(content, structured, is_error)
mcp_close(conn)                       # close stdin, wait, kill_tree
```

stdio children get the MCP environment allowlist [G6 §1.6], ASCII-only JSON through the write-all
loop, reassembled `poll_io` lines (16 MiB cap) and a per-server stderr log. Era: a `server/discover`
probe (5 s) else legacy `initialize`; over HTTP the 400 body decides; cached per server. Progress
re-arms the idle timeout; timeouts and interrupts send `notifications/cancelled`. MRTR
`input_required` (at most 5 rounds): elicitation goes to the ask UI, roots answer the project
directory, sampling is refused. OAuth: RFC 9728 discovery, pre-registered > CIMD > DCR, PKCE S256; a
tool call never opens a browser (a classed condition says `gptr_mcp(login = "<server>")`). Tools
become R closures from their JSON Schema with argument coercion [16 §4, 06 §4].

### 6.12 Sub-agent backends and orchestration (spec kind `backend`) [15 §4.2-4.5]

```r
gptr_spec("backend", "inline",
  start = function(spec, ctx) NULL,   # spec: agent def, prompt, objects, export, model, mode, depth
                                      # -> handle: list(session, fds = function() NULL,
                                      #    poll = function() NULL, cancel = function() NULL)
  capabilities = list(parallel = "io", live_objects = TRUE, ask = "queue"))
```

| Backend | Process | Objects | Parallelism | Ask/permission |
|---|---|---|---|---|
| `inline` (default) | same R process, same reactor | zero-copy reads through `new.env(parent = envir)`; writes stay in the overlay; exports on success | I/O interleaved; tools serialised through the FIFO | queued to the parent UI one at a time |
| `worker` | `callr::r_bg(worker_main, package = "gptr", supervise = TRUE, cleanup_tree = TRUE, user_profile = FALSE, libpath = .libPaths())`, environment scrubbed with `NA` entries [G6 §1.6] | `objects =` serialised; results by `export =` | CPU-parallel | JSONL `permission_request`/`ask` forwarded to the parent over stdin/stdout |
| `cli` | the claude or codex adapter's process | none (files only) | parallel processes | CLI permission mapping (6.13) |

Inline children run the `minimal` preset, inherit the parent's mode (can only tighten), get their own
L'Ecuyer RNG stream swapped in around tool evaluations (the user's `.Random.seed` is untouched), and
have code containing super-assignment, `assign(envir = )`, `:=` or `set*()` classified at level 2
(denied in parallel runs, where results must be exported). Limits: 8 tasks per call, 8 inline and 4
CLI active, `min(4, cores - 1)` workers (2 under `_R_CHECK_LIMIT_CORES_`), depth 1 (children get no
`agent` tool and nested `gptr()` inside a child errors), 50 KB of child text returned per task
[15 §3.7]. Orchestration (`agents =`, `parallel =`, `gptr_parallel()`) builds a parent session whose
`text` concatenates `### <name> (<model>)` sections, whose `value` is the named list of child values,
and whose `children` hold the child sessions; piping the parent continues it with the children's
reports attached as a user-role `<agent_reports>` block (sub-agent output is data [G4 §3.1]).

### 6.13 CLI providers (`cli-claude.R`, `cli-codex.R`) [07 §4, 08 §4, 15 §3.4]

`cli-claude` (alias `claude_code`, provider id `claude-cli`): one long-lived process per session,
`claude -p --input-format stream-json --output-format stream-json --verbose
--include-partial-messages --tools "" --strict-mcp-config --setting-sources "" --mcp-config <file>
--permission-prompt-tool stdio --system-prompt-file <file> --model <full id>` (never `--bare`) [07 §4].
The MCP config declares one `sdk` server named `gptr`; its `mcp_message` control requests are
answered in R by `mcp_dispatch_local()`, exposing the session's `r`, `read`, `write` and `edit`, so
Claude evaluates R in the live session; `can_use_tool` requests go to `tool_gate()`; `stream_event`
lines feed the Anthropic decoder. Interrupt: control request, then `kill_tree()`. API-key variables
are scrubbed so the plan is billed [G6 §1.6]; native `claude.exe` on Windows, no free text on argv.
Opt-in with a one-time notice (terms UNCERTAIN).

`cli-codex` (alias `codex`): `codex exec --json -` per turn, prompt on stdin, `--sandbox read-only`
(plan) or `workspace-write` (edits, auto); in `manual`, one up-front approval because headless exec
cannot prompt [08 §4]; follow-ups via `codex exec resume <thread>` when supported (UNCERTAIN), else a
new thread with a synthetic history. Codex acts on files with its own tools and cannot see live R
objects in v1; the console states its 19-38K extra input tokens per turn.

### 6.14 System 1 client (`s1-client.R`) [04 §4, 04a]

```r
s1_call(prompt, context, choices = NULL, levels = NULL, threshold = 0.5, min_confidence = 0,
        uncertain = NA, model, session = NULL, envir)
# -> gptr_decision | gptr_choice | gptr_score
s1_states(context)                     # batch rule: atomic vector/unnamed list -> one state per element,
                                       # data frame -> per row, named list -> one, I(x) -> one
s1_question(prompt, label, choices, levels)   # -> wire question (noul | choice | score), validated locally
```

Algorithm: build states (field name = the context label, instructions append "The input is in
`<label>`."), look up each element in the S1 cache (key = sha256 of canonical JSON of endpoint,
model, question, type, criteria and input; radix key order [14 verification]), send only misses as
concurrent reactor requests (`max_active = 8`, per-host limiter from catalog data), bounded retry
rounds (at most 3; resubmit failed elements only; honour retry-after; cap 60 s), parse by name,
threshold, apply `min_confidence`/`uncertain` (`NA`, `TRUE`, `FALSE`, `"stop"` or a function of
`(state, answer)`), write the cache (in memory before `gptr_init()`), emit `decision`. A vectorised
call with failures returns `NA` elements and warns once; a scalar call raises
`gptr_error_s1_<kind>`. `choices = factor(...)` returns a factor.

### 6.15 Compaction (spec kind `compactor`, `session-compact.R`) [G4 §4.4]

```r
compaction_threshold(window, soft_cap = getOption("gptr.compact_at", 200000))
should_compact(tokens, window, idle_s, ttl_s)
compact_checkpoint(session, reason, focus = NULL)   # builtin:compaction's compact()
extract_state(entries)   # user messages, objects + creating code, notes, files, skills, plan
```

Threshold `min(window - min(max(30000, 0.10 * window), 0.25 * window), 200000)`; cold rule (idle
beyond the tail TTL and at least 100k tokens); checks only between tool rounds, before a new prompt,
or after an overflow error. The checkpoint request is sent in-conversation (a cache read), with
`max_tokens = 2048` and a tool-calling reply rejected; the compaction entry holds the reused project
and environment blocks, the `<checkpoint>` (model summary plus harness state), mode, a fresh
workspace block and active skills within budget; `keep_recent = 0`. No micro-compaction in place.

### 6.16 Secrets and redaction (`auth-*.R`) [G6 §4]

```r
secret_register(value, name, source)     # only entry point for values; returns a gptr_secret handle
secret_value(h, origin)                  # only called while building curl headers; origin-bound
redact(x, profile = c("persist", "context", "stream", "code", "user_data"))
redact_stream(profile)                   # bounded hold-back across chunks
child_env(profile = c("mcp", "worker", "claude", "codex", "helper"), pass = character())
```

Redaction at ingress for every sink (transcript entries, JSONL, documents, spill files, caches,
console, conditions, wire log); opaque replay fields are never touched; a literal secret in recorded
code becomes `Sys.getenv("NAME")`.

### 6.17 `ctx` (`ext-ctx.R`), the object every handler receives [G1 §3.3]

```r
ctx$session            # read-only view (id, model, mode, status, usage, text)
ctx$envir              # evaluation environment
ctx$mode(); ctx$model(); ctx$has_ui(); ctx$ui()      # ui: select(), input(), questions(), notify()
ctx$risk(code)         # the advisory classifier (perm-classify.R)
ctx$redact(x, profile)
ctx$execute_tool(name, input)            # nested call through the same gate
ctx$send(text, as = c("steer", "follow_up"))
ctx$append_entry(type, data)             # custom entries in the store
ctx$abort(reason)
ctx$decide(question, x, ...)             # System 1 through gptr(model = <configured S1>)
ctx$usage(); ctx$state()                 # per-session, per-plugin environment
ctx$emit(channel, data)                  # inter-plugin bus, channels "<plugin>:<topic>"
```

---

## 7. Positions on open decisions and cross-track conflicts

### 7.1 Decision register D-01..D-28

| ID | Position | Rationale and evidence |
|---|---|---|
| D-01 | Settled by S-10. The own layer sits directly on **curl** (no httr2). | httr2 streaming is batched or blocks the loop until headers [10a E1/E2, V-7/V-8], interrupts before first byte fail [02 §5.4], `req_perform_parallel` retries without bound [04 §2.16]; curl multi is the only path that survived resumed interrupts [02]. Dropping httr2 keeps 10 packages out of the closure (httr2, glue, lifecycle, magrittr, openssl, rappdirs, vctrs, withr, askpass, sys) [P-A exp]. |
| D-02 | S3 classes; environments for session, registry, ctx, reactor, runs; classed lists and base-typed vectors for values. No R6/S7. | Closure methods in locked environments 1.6-1.9 µs vs R6 3.8-4.5 µs; R6$new 47-76 µs [G1 §2.3]; no validators on hot paths [10a §16]. R6 arrives transitively through callr but is not used. |
| D-03 | Direct tools: `read`, `write`, `edit`, `r` (REQ-10's four) plus `ask` when a human is present. `grep`, `find`, `ls`, `artifact`, `agent` exist with exposure `r` (R functions in `gptr_tools`) and can be promoted (`tools = "+grep"` or preset `full`). No `shell` tool (S-4); `gptr_tools$run()/sh()` instead. | REQ-10 names the four; Claude Code itself moved search into its code tool [20 §2]; `r` exposure costs about 36 tokens per function vs about 328 direct [G1 §2.5]; the 7-tool array costs 1,199 vs 686 tokens [G4 §2.8]. `ask` is justified by REQ-36 and north-star §12. |
| D-04 | `envir = parent.frame()` captured at the call; explicit `envir =`; magrittr mask detection; inline sub-agents use `new.env(parent = envir)` without binding locks. | [12 §2.B4]; locks break copy-safety [P-A exp]. |
| D-05 | `gptr()` returns the session environment. Idle session + pipe = follow-up turn; running session + pipe = steering message (same queue as the pause menu); `gptr_fork()` is the explicit branch and is recorded as a block whose header carries `fork=`; data-first pipe is told apart by the class of the first argument; System 1 returns typed vectors; interactive `gptr()` returns the session invisibly. `background = TRUE` is v1.x. | S-8, [10a INFRA-14], [G1 §4.6]; background needs `later` pumping whose behaviour in RStudio/Positron/Jupyter is unverified [15 §2.5]. |
| D-06 | Typed vectors: `gptr_decision` (logical), `gptr_choice` (classed character; `choices = factor(...)` returns a factor), `gptr_score` (double). Default threshold 0.5, no abstention; `min_confidence` + `uncertain` (`NA`, `TRUE`, `FALSE`, `"stop"`, function). Emulation through a System 2 model is opt-in (`gptr_config(system1 = "emulate:<model>")`), never silent. | A factor is truthy in `if()` and switches on its integer code [04 §2.15]; silent emulation would spend System 2 tokens and return uncalibrated numbers [04 §4.8]. |
| D-07 | rlang `enquo`/`enquos` capture (overturning base-only); known name wins over a same-named variable; `!!` escape; unknown bound symbol takes its character value; unknown unbound symbol is a literal; other calls evaluate in an alias mask. | Forwarded dots resolve wrongly with base `substitute()` [12 §2.D2]; library() semantics [12 §2.D1, 10 §6]. |
| D-08 | Block grammar, ownership and replay modes of report 14 unchanged; `gptr()` never executes a recorded block; under `source()`/Rscript live regeneration downgrades to replay with a warning; `gptr_source()` does live regeneration. | [14 §3.1, §4.4]. |
| D-09 | Two forms: JSONL v3 tree per session (append-only) and the runnable document. | [02 §4.6, 10a INFRA-13]. |
| D-10 | `.gptr/` only through `gptr_init(path)` (no default; asks interactively) or an interactive yes; otherwise `tempdir()`. User-level config/cache/data under `tools::R_user_dir("gptr", ...)`, data store only with consent, caches pruned. | [13 §2, C-list]; CRAN "actively managed" proviso [17 verification]. |
| D-11 | Modes `plan`, `manual` (default), `edits`, `auto`; risk levels 0-4; rules `tool(spec)` with deny > ask > allow > mode; critical guard in `auto`; advisory classifier documented as not a security boundary. | [18 §3.7-3.8, §4.7], north-star §12. |
| D-12 | Backends `inline` (default for every agent, including parallel fan-out), `worker` (callr, explicit), `cli` (claude/codex models). `fork` is v1.x. | Inline gives zero-copy reads and I/O concurrency (5 agents 5.2 s vs 14 s sequential [15 §2.3]); fork is unsafe in GUIs [15 §2.8]. |
| D-13 | gptr-owned reactor: curl multi (`pipewait = 0`) + `processx::poll` over curl fds and child pipes, one per top-level call. No coro/promises/later in the core. | [15 §4.1, 10a INFRA-01/16]; PIPEWAIT serialises streams [15 §2.2]. |
| D-14 | Own MCP client (processx stdio, curl HTTP through the reactor), both protocol eras, config import, tools as R functions (exposure `r`, 3,000-token signature budget). gptr as MCP *server* only in-process for the claude CLI (`sdk` transport) in v1; the httpuv HTTP server is v1.x. | [16 §4, 06 §4]; the HTTP fallback needs `later` pumping and aborts R tools after 60 s without a per-server timeout [07 verification]. |
| D-15 | `claude` CLI via stream-json + control protocol (opt-in, notice); `codex exec --json`. Native OAuth for plans: none in v1 (Sign in with ChatGPT is v1.x). | [07 §4, 08 §4]; Pi's stealth mode must not be ported [03 §2.13]. |
| D-16 | Agent Skills folders; extensions are `function(gptr)` factories; plugins are directories or R packages with `inst/gptr/plugin.json`; skills/prompts of attached packages are auto-available, code only from enabled plugins; lazy activation. | [05 §4.10, G1 §4.4, 16 §4.9]. |
| D-17 | Shiny app in a `callr::r_bg` child (supervise, cleanup_tree), snapshot with `saveRDS(compress = FALSE)`, registry under `.gptr/artifacts` or `tempdir()`, validation ladder parse -> launch -> HTTP 200 -> optional chromote session check with screenshot. | [17 §4]; shiny 1.14 `startApp()` in-process stalls when the console is busy and allows one app [17 verification]. |
| D-18 | `provider/id[:thinking]` plus aliases resolved from family and release date; pruned models.dev snapshot in `inst/extdata`; refresh only on request. Default chat model: `anthropic/claude-sonnet-5-5` when an Anthropic key exists, else the first configured provider's catalog default (Gemini `gemini-3.8-flash`, OpenAI `gpt-6-sol`, local first model); full ids pinned. | [09 §4]; the north-star banner shows Sonnet 5.5; Opus 5.5 costs twice as much [07 §1]. |
| D-19 | Provider usage + calibrated estimator (chars/4 prose and code, chars/2 tool output, CJK 1/char); compaction threshold formula of G4; tool output truncated at entry (20,000 chars / 800 lines, head 40% + tail 60%, spill file; 8,000 chars once context passes half the threshold). | chars/4 underestimates printed R output by about 51% [21 §2.8] (-41% in G4 §4.5). |
| D-20 | Imports: jsonlite, curl, processx, callr, rlang, cli, yaml (section 8). | Each has a load-bearing use; no LLM package (S-10). |
| D-21 | No compiled code. | No candidate met the bar [21]. |
| D-22 | Vault + handles, own `.env` parser with aliases, per-request resolver with origin binding, redaction at ingress, child-environment profiles. | [G6 §1, §4]. |
| D-23 | `Depends: R (>= 4.2.0)`. | UTF-8 native on current Windows, pipe placeholder [13 §2]. |
| D-24 | Fake provider, base-R SSE mock under `skip_on_cran`, wire fixtures, adapter conformance suite, copy-safety and prefix tests, live tests gated by `GPTR_LIVE_TESTS`. | [10a INFRA-24, 13 §5, G4 §4.9]. |
| D-25 | Pi-derived canonical events with gptr additions (6.3); Claude/Codex names import-only. | [G1 §3.2]; one vocabulary for plugins. |
| D-26 | cli rendering; chunk-invariant markdown stream; interrupt pause menu; `!`/`!!`; tier-1 slash commands (section 9.4). | [18 §4]. |
| D-27 | No `{gptr}` chunk engine in v1 (v1.x, off by default); `gptr()` in R chunks plus `knit_print`; `GPTR_REPLAY=replay` for vignette builds. | Engine relaxes S-2 [14 §4.6]. |
| D-28 | `gptr()` + 27 `gptr_*` names; `agent()` only as a data-mask alias. | Collision scan [G1 §4.7, 10 Q4]. |

### 7.2 Cross-track conflicts (critic's list 1-33; the task's known conflicts 1-18 are the same items)

| # | Conflict | Resolution |
|---|---|---|
| 1 | R6 vs S3 + environments | S3 + environments everywhere (D-02). |
| 2 | Transport and SSE parsing | Own reactor on curl multi; own vectorised byte-level SSE splitter (flushes a final unterminated event, which `resp_stream_sse` drops [08 verification]; 17x faster than `resp_stream_sse` [21 verification]); no httr2 at all, so its minimum version and parallel retry bug are moot. |
| 3 | Imports budget | 7 Imports (section 8). yaml in Imports (skills are a headline; a hand parser lost skills [05]); httpuv and openssl in Suggests (only MCP OAuth); later not used in v1. |
| 4 | NSE capture and ambiguity | rlang capture; known name wins; `!!` escape (D-07). The rules of 05 ("a character variable wins") and 09 ("a bound variable wins") are rejected because `tidyllm::claude`, `vitals::codex` and `future::plan` are common bindings [10 Q4]. |
| 5 | Evaluator and plot size | Hand-rolled evaluator [12]; plots 768x512 at res 96 (532 tokens) for model images; the 1000x700 size of 17 is used only for artifact screenshots' default viewport. evaluate is not a dependency. |
| 6 | Default tool surface and R tool name | Four direct tools + `ask` when interactive; the R tool is `r`; no todo tool; edit results are message-only, plus a unified diff (at most 4 KB) only when the fuzzy fallback changed matching (the case where the model must see what happened [11 §4]). apply_patch is v1.x. |
| 7 | Dispatcher and MCP naming | One exported object `gptr_tools`; MCP tools `gptr_tools$<server>$<tool>()`; no `tools`, no `mcp` object, no `mcp_*` exports; the prompt text of G4 changes only in `<r_session>` and the R-function catalog. |
| 8 | Default sub-agent backend and limits | `inline` for everything unless the agent file, model (CLI) or call says otherwise; no `auto` mode; limits in 6.12 (depth 1, 8 tasks, 8 inline / 4 CLI active). Naming `worker` (D-12). |
| 9 | System 1 API | Single gateway, classed character choice, `min_confidence` + `uncertain` (D-06); no `decide()`/`classify()` exports; requests on the reactor with bounded rounds (INFRA-18). |
| 10 | Return value | The session object (S-8); `gptr_result` is not used; `$value` from `gptr_return()`. |
| 11 | Claude plan bridge | Unmodified CLI, `sdk` in-process MCP over the control protocol, no httpuv fallback in v1; opt-in with notice; provider id `claude-cli` with alias `claude_code` (the name-use question is flagged for the maintainer [07 verification]). |
| 12 | ChatGPT plan route | `codex exec --json` in v1 (verified live [08]); Sign in with ChatGPT and app-server are v1.x (preview/experimental, unverified eligibility). |
| 13 | MCP protocol eras | Both, via probe and cached era (6.11). |
| 14 | Session format vs compaction | Pi v3 JSONL tree, append-only; compaction appends a checkpoint; no micro-compaction in place (it costs +32% and invalidates thinking [G4 §2.10]). |
| 15 | Workspace consent and locations | `gptr_init(path)` without default that asks interactively (north-star §9 works at the console); tempdir otherwise; artifacts under `.gptr/artifacts` only in a consented workspace (north-star §8 banner shows `.gptr/ found`). S1 cache in memory before init. |
| 16 | Steering channels | One queue per session with two lists (steer, follow_up); producers: pipe into a running session, pause menu, `ctx$send()`, parent agents; delivered after the complete tool-result entry (INFRA-12). |
| 17 | Script-as-history under Rscript/source | Report 14 as is: deferred Rscript writes, content-based matching, `live` via `gptr_source()`/knitr/IDE only; reading `source()` frame locals is wrapped in `tryCatch` and degrades to "no document" (CRAN grey zone flagged). |
| 18 | Copy-safety | Never hold references: no `mget()` snapshots of objects above `gptr.undo_max_bytes` (default 50 MB; `/undo` restores files and conversation, and objects only when a snapshot fits); no binding locks; fingerprints instead of full hashes above 50 MB; tracemem suite in CI. |
| 19 | S1 decisions in the history document | S1 calls written by the user or the agent are code in the document; top-level S1 calls get a one-line summary block; decisions inside control flow go only to the cache and the JSONL `gptr.decision` entries (REQ-26c satisfied by the code itself). |
| 20 | Project instructions placement | G4: AGENTS.md/CLAUDE.md root to cwd, then `.gptr/vignette.Rmd` last and additive, as user-role data in the first user message with a 1 h anchor; precedence stated once in `<context>`; 6,000-token budget, 64 KiB cap. |
| 21 | Hook taxonomy | Pi-derived names (6.3). |
| 22 | Permission modes and plan mode | Mode names of D-11. Plan mode: level <= 1 R code runs in a scratch child environment, everything else is denied with "describe this change in your plan"; the final answer is saved to `.gptr/plans/<ts>.md` (workspace only) and handed once to the next `gptr()` call in the same R process as a `<plan>` block, which makes north-star §12's second call work without a pipe. |
| 23 | Compaction thresholds and estimator | G4 formula; chars/2 for tool output. |
| 24 | Skill catalog budget and activation | Compact catalog with budget `max(8000 chars, 1% of the context window)` dropping least-recently-used descriptions first; activation through `read` (no skill tool), `skills =` preload, `/skill:name`. |
| 25 | Agent files: Bash mapping, directories | `Bash`/`PowerShell` map to `r` (S-4); directories `.gptr/agents`, `.claude/agents`, `.pi/agents` (project, trusted) and user-level equivalents; `.codex/agents` (TOML) is v1.x. |
| 26 | Opt-in shell tool | None. Compact R helpers instead: `gptr_tools$run(cmd, args)` (processx, no shell, cross-platform) and `gptr_tools$sh(script)` (detected system shell), both risk level 3. |
| 27 | Exported names | Section 4. |
| 28 | knitr engine | v1.x (D-27). |
| 29 | File-tool recipes | 21's verified best pure R: `readBin` + `grepRaw(fixed)` prefilter for literals, whole-file `(?m)` PCRE prefilter for regexes, NUL sniff of 8,000 bytes, never `readLines` per file; big files: `grepRaw` newline scan with a sparse index above 20 MB; diff: patience + Myers capped at D = 256, no diffobj; `find` follows Pi's `**/` prefix rule for patterns containing `/` (model behaviour transfers) [11 verification]. |
| 30 | Event loop integration | One reactor; no httpuv/later in the core; artifacts rely on `supervise = TRUE` instead of a parent-PID watchdog; background and HTTP MCP serving are v1.x. |
| 31 | S2 cache committed vs privacy | S2 answer cache is gitignored by default (`cache_commit = FALSE`), S1 cache (hashes and answers only) is committed; everything redacted at ingress. |
| 32 | Default models | D-18. |
| 33 | Retry constants | Transport: INFRA-06 constants (6.2). Agent level: 2 retries (2 s, 4 s) for mid-stream errors after committed deltas. S1: bounded rounds, 3 attempts. Spend-cap 429 never retried. |

---

## 8. Dependencies

`Depends: R (>= 4.2.0)`. Imports (7; dependency closure: these plus R6 and ps, and otel with callr
3.8.0 [P-A exp]; compare 16 packages for httr2 + jsonlite + cli + processx [10 §5]):

| Import | Minimum | Load-bearing use | Why not base R |
|---|---|---|---|
| jsonlite | 1.8.8 | every wire body, JSONL, settings, schemas | no JSON in base |
| curl | 6.0.0 | reactor transport (multi handles, `multi_fdset`, `multi_cancel`), URL escaping | only curl multi streams interruptibly [02, 10a INFRA-01] |
| processx | 3.8.0 | `poll()` over curl fds and pipes, MCP stdio, CLI providers, `kill_tree` | `system2()` cannot poll or stream |
| callr | 3.7.0 | worker sub-agents and artifact children with the package namespace | shipping functions and args safely; `user_profile = FALSE` |
| rlang | 1.1.0 | `enquo`/`enquos`/`eval_tidy` (NSE correctness), `obj_address`, `hash` | base capture resolves forwarded dots wrongly [12 §2.D2] |
| cli | 3.6.0 | terminal capability detection, rendering, `hash_sha256` (ids, cache keys) | front-end quirks are encoded there [18 §2.1.5] |
| yaml | 2.3.0 | SKILL.md, agent and prompt frontmatter | block scalars in real skills [05 §5] |

Suggests (each behind `requireNamespace()` with a base fallback or a `gptr_error_missing_package`):
testthat (>= 3.2.0), withr, knitr, rmarkdown, shiny, bslib, chromote, ragg, httpuv (MCP OAuth
loopback), openssl (PKCE, faster base64), rstudioapi, vctrs (S1 methods), reticulate
(`gptr_tools$py`), DBI (`gptr_tools$sql`), stringi (NFKC in the edit fallback), magick (image
resize), filelock, ps (free RAM in `<r_env>`; installed with processx). Not used: httr2, R6, S7,
evaluate, digest, lobstr, fs, vroom, glue, later, promises, coro, mirai, any R LLM package (S-10).
SystemRequirements: optional external programs `claude` and `codex`.

---

## 9. The model-facing tool surface and system prompt

### 9.1 Direct tools (JSON Schema sketches)

| Tool | Schema | Permission class |
|---|---|---|
| `read` | Pi's schema verbatim: `{path: string, offset?: number, limit?: number}`; images by magic bytes | read (level 0 in project, 1 outside, 2 secret/protected) |
| `write` | Pi's: `{path: string, content: string}`; atomic, encoding-preserving | write (level 2 in project, 3 protected/outside) |
| `edit` | Pi's: `{path: string, edits: [{oldText: string, newText: string}]}` plus optional `replaceAll: boolean` per edit; routed through the document backend when the path is the recording document | write |
| `r` | `{code: string, record?: boolean (default true), note?: string, timeout?: number (default 300)}` (G4 §3.3 text, 202 tokens) | eval: level from the classifier (0-4) |
| `ask` (human present only) | `{questions: [{id, question, type?: "single", "multi" or "text", options?: [{label, description?}] (<= 9), allow_other?, default?}] (1-4)}`; descriptions trimmed to about 200 tokens [18 §3.6] | interact (never gated; sequential) |

Optional direct tools (preset `full` or `tools = "+name"`): `grep` `{pattern, path?, glob?,
ignoreCase?, literal?, context?, limit?, output?: content|files|count}`, `find` `{pattern, path?,
limit?, sort?: path|mtime|size}`, `ls` `{path?, limit?, sort?: name|mtime|size}` [01 §4.4, 11 §4];
`artifact` [17 §3.2]; `agent` [15 §3.5]. Every direct tool's description is at most 400 tokens
(checked by `gptr_check()`).

### 9.2 R-function surface (`gptr_tools`, exposure `r`)

Listed in the `<r_session>` section as one line each (about 36 tokens per function [G1 §2.5]):

```r
gptr_tools$grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE,
                context = 0L, limit = 100L)          # data frame file/line/text; respects .gitignore
gptr_tools$find(pattern, path = ".", sort = "path", limit = 1000L)   # files by glob
gptr_tools$ls(path = ".", sort = "name")                             # directory listing
gptr_tools$run(cmd, args = character(), timeout = 60, wd = NULL)     # program, no shell
gptr_tools$sh(script, timeout = 60)                                  # system shell script
gptr_tools$py(code)                                                  # Python via reticulate
gptr_tools$sql(con, query, n = 1000L)                                # DBI query, capped
gptr_tools$artifact(title, code, data = character(), id = NULL, edits = NULL)   # Shiny app
gptr_tools$search(words); gptr_tools$help(name)                      # find and describe tools
gptr("task", data, model = <alias>)                                  # sub-agent; returns a session
gptr_return(x)                                                       # hand x back to the caller
```

Results are R objects with compact print methods (a `gptr_process_result` prints status and a
truncated stdout/stderr; a grep result prints like the grep tool); only what the model prints
enters the context. `artifact()` also attaches the app screenshot to the `r` result as an image.
MCP and plugin tools follow in a `<r_functions>` T1 section: `server: n tools, k shown` and one
signature line per tool within 3,000 tokens; overflow is reachable with `gptr_tools$search()`.

### 9.3 System prompt outline and first message

Frozen at session start in two blocks [G4 §3.1-3.2], text adapted from G4's verbatim sections with
the names of this proposal:

| Tier | Section (order) | Included when | Budget (o200k est.) |
|---|---|---|---|
| T0 | `preamble` | always | 80 |
| T0 | `tools` (one-line snippets of direct tools) | always | 90 |
| T0 | `rules` (Pi's edit guidelines; `=` and `\|>`; concise; name created objects) | always | 260 |
| T0 | `r_session` (live session, small steps, never reload, `gptr_tools` catalog, polyglot glue, sub-agents via `gptr()`, `gptr_return()`, forbidden calls) | `r` active | 550 |
| T0 | `r_performance` short form [19 §3.1] | `r` active | 130 |
| T0 | `documents` (record/note, edit earlier blocks) | recording on | 190 |
| T0 | `system1` | S1 provider configured | 125 |
| T0 | `modes`, `context` | always | 85 + 105 |
| T1 | `skills` compact catalog | skills visible | 2,000 |
| T1 | `r_functions` (MCP and plugin signatures) | any configured | 3,000 |
| T1 | `r_env` (R, platform, cores, RAM, installed/not-loadable/missing packages) [19 §3.2] | `r` active | 450 |
| T1 | `addendum` (`APPEND_SYSTEM.md`, trusted) | present | 1,000 |

First user message (rendered once, reused after compaction): `<project_instructions>` (cache anchor)
-> `<environment>` (date, cwd, project root, document, front end, R version, RAM free) -> `<mode>`
(with a non-interactive note when no human) -> `<plan>` (pending plan hand-off, once) ->
`<workspace>` (at most 12 lines, largest first) -> `<attached>` blocks -> the prompt. Later turns
append `<workspace_changes>` (only when non-empty), `<skill_content>`, steering relays and operator
entries (mode, model, section patch).

### 9.4 Console surface (not model-visible)

REPL input: text prompt; `!expr` (evaluated, added to context), `!!expr` (not added), fenced R
code blocks, `"""` multi-line prompts, `@file`/`@object` mentions. Tier-1 commands:
`/help`, `/exit`, `/model`, `/mode` (`/plan`), `/tools`, `/env`, `/compact`, `/cost`, `/context`,
`/status`, `/clear`, `/resume`, `/save`, `/skills`, `/skill:<name>`, `/mcp`, `/undo`, `/retry`, plus
prompt templates as `/<name>` [18 §4.4]. Commands are recorded as comments in transcripts.

---

## 10. Walkthroughs

Token figures are estimates (o200k proxies from G4 §2.8 and 12 §3.13; Claude's tokenizer is not
public). Prices are Sonnet 5.5 ($2 in, $10 out per MTok, cache read 0.1x, 5-minute write 1.25x,
1-hour write 2x [07 §1]).

### 10.1 Example 1 — interactive session on a 5 GB object

1. `library(gptr)`: `.onLoad` registers built-in plugin records (declarative, 3-8 ms [G1 §2.4]) and
   lazy S3 methods; no disk, no network. `pbmc = readRDS(...)` is ordinary R.
2. `gptr()`: no dots, no prompt, `gptr_has_human()` TRUE, so `builtin:console` starts
   `console_repl(session, envir = parent.frame())` (`globalenv()` at top level, never named by the
   package). Session creation: config merge (trusted `.gptr/settings.json`: `model = sonnet`, mode
   `manual`); secrets discovered into the vault; registry resolution (built-ins, user plugins, project
   skills); `session_start` hooks; the system prompt is frozen (T0 `lean` with `ask`, T1 with
   `<r_env>` from the no-load package probe [19 §3.2]); `store_open()` writes the JSONL header in
   `.gptr/sessions/`; the user-expression task callback is registered; the transcript target is
   chosen once (the IDE's `analysis.R` if the user agrees, remembered in `settings.local.json`). The
   banner uses `workspace_block()` (`pbmc <Seurat ... 5.1 GB>`, `object.size` cached by address, no
   copy [12 §2.C4]).
3. The prompt passes the `input` hook chain and becomes a `user` entry: `<project_instructions>`
   (vignette.Rmd text, never executed), `<environment>`, `<mode name="manual">`, `<workspace>`, prompt.
4. `run_new()` + `reactor_new()`; `build_request()` sends model, stream, top-level `cache_control`,
   adaptive thinking (summarized display), 5 tools, `system` [T0 with a 1 h breakpoint, T1] and the
   first message with a 1 h anchor on the project block: about 2,890 + 420 tokens.
5. SSE bytes -> vectorised splitter -> Anthropic decoder -> `message_update` deltas rendered by the
   console; a `tool_call` `r {code: "pbmc = FindNeighbors(pbmc, dims = 1:30)"}` completes.
6. `dispatch_tools()`: validation; the classifier rates an overwrite of `pbmc` above
   `gptr.protect_size` as level 3; `manual` returns `ask`; the console shows north-star §1's one-line
   prompt (detail view one key away) and notes `/undo` cannot restore 5.1 GB. `y`.
7. `eval_r()` runs in `globalenv()`: FindNeighbors mutates the object in memory; a ~40-token result;
   `env_diff()` reports `~ pbmc`; entries appended to the store at `message_end`.
8. Requests 2-4 reuse the cached prefix; `FindClusters` and `markers = FindAllMarkers(...)` (level 1,
   new object) ask again unless `[a]lways` added a session rule such as `r(fn:FindClusters)`; the
   answer streams; `agent_end`.
9. `builtin:documents` writes the transcript block (north-star §7): the call, the three recorded
   codes, `#>` output, `## Decision:` from `note`; `document_write` hooks may veto or patch it.
10. `!dim(markers)` evaluates in `envir`, queues a user-role note for the next turn and is recorded
    as `# direct R` code; `/mode auto` appends an operator `mode` entry at the next turn (no prompt
    rebuild); `/exit` fires `session_end`, closes the store and returns the session invisibly.
    `pbmc` (clustered) and `markers` stay in `globalenv()`.

The model saw the frozen system prompt, one first message, three short tool results and its answer,
never the data. Disk: the JSONL file and the transcript block. About 15,400 input tokens (11,000
cache reads) and 1,350 output tokens, roughly $0.03 (section 14.3).

### 10.2 Example 3 — the pipe steers one session

1. The pipe chain is nested calls; each `gptr()` evaluates its first dot first, so the innermost call
   runs first: new session `s` (Sonnet 5.5) loads `data/counts.csv` with `r` (via
   `data.table::fread` because `<r_env>` lists it) and creates `counts_norm`.
2. The middle call finds an idle `gptr_session` as first dot: a follow-up `user` entry on the same
   session (plus `<workspace_changes>` only if something changed) and another run (`pca` created).
3. The outer call resolves `opus` (known name, so a variable `opus` cannot shadow it) to
   `anthropic/claude-opus-5-5`; the hand-off transform keeps text and tool pairs and drops Sonnet's
   thinking signatures [10a INFRA-08]; Opus's cache starts cold. The plot appears on the user's device
   and returns to the model as a 768x512 PNG (532 tokens). The value is `s` with three turns; a
   top-level statement gets three blocks (`call=1..3`).
4. `qc = gptr("Run QC ...", pbmc)`: new session with `<attached name="pbmc">` (`gptr_describe()`, at
   most 300 tokens, no copy); the agent calls `gptr_return(qc_flags)`, so `qc$value` is set.
5. `table(pbmc$percent.mt > 20)` is logged by the task callback; `qc |> gptr("Use 15% ...")` continues
   the idle `qc` with `<workspace_changes>` (`user ran: table(...)`) and a new `gptr_return()`, so
   `qc$value` reflects the steered state (reference semantics).
6. `gptr_fork(qc) |> gptr("Try a 10% cut-off as well")`: the entry list is copied (immutable entries,
   no deep copy), a new JSONL file names `qc`'s as `parentSession`, no listeners or queues are
   copied; the fork shares the workspace (`isolate = FALSE`) and gets an operator note to create new
   object names; `qc` is untouched; the block header records `fork=<qc id>`.

### 10.3 Example 4 — System 1 in control flow

1. `if (gptr("Is this abstract about a randomised controlled trial?", abstract, model = jev))`: the
   literal is the prompt, `abstract` the context, `jev` resolves to `typesafe/jev-latest` (type
   `classifier`), so the route is `s1_call()`.
2. One state `{"abstract": "<text>"}`; question `{type: "noul", instructions: "... The input is in
   abstract.", criteria: {true: "yes", false: "no"}}` (`bool` is `noul` on the wire [04a]).
3. Cache lookup (memory before `gptr_init()`, else `.gptr/cache/s1/`, which stores the input hash,
   never the input); a miss is one reactor request with the key materialised only for the TypeSafe
   origin; `noul: 0.93`, about 280 input tokens (about $0.00001).
4. The result `structure(TRUE, class = c("gptr_decision", "gptr_s1"), prob = 0.93, ...)` goes straight
   into `if()`; a `decision` event fires; nothing is written to the document (inside `if`).
5. `is_rct = gptr("...", abstracts, model = jev)` at top level: 20 states, misses only, 20 concurrent
   requests (8 active; about 0.4-1 s [04a]), at most 3 bounded retry rounds; `table(is_rct)` and
   `attr(is_rct, "prob")` work; the document gets `#> gptr_decision: 14 TRUE / 6 FALSE (jev-1.13.0,
   2026-09-29)`.
6. `choices = c(...)` gives a `choice` question; probabilities are re-keyed by option name (the API
   reorders them [04a]); the result is a `gptr_choice` with a probability matrix (a factor if
   `choices` is a factor).
7. `while (gptr(..., diagnostics(fit), model = jev))`: one request per iteration unless cached; a data
   frame would be one state per row, so `I(diagnostics(fit))` forces a single state.

### 10.4 Example 6 — sub-agents in parallel and across providers

1. `agents = list(...)` is captured with `rlang::enquo()` and evaluated in a data mask binding
   `agent` to `gptr_agent`, which applies the NSE rule: `stats` -> Opus inline, `code` -> the `codex`
   CLI (backend `cli`), `biology` -> `google/gemini-3.8-flash` inline.
2. Parent session `P` (its model not called); `subagent-parallel.R` starts two HTTP streams and one
   `codex exec --json -` process on one reactor (sandbox `read-only` for a review). Inline children use
   the `minimal` preset (~1,260 static tokens), a preloaded `<skill_content>`, an overlay
   `new.env(parent = envir)` and their own RNG stream.
3. Children `read` `analysis.R` (level 0) and inspect with `r` (`record = false`); their tool calls
   are serialised through the FIFO while streams buffer; `ask` requests queue to the console.
4. `P$text` concatenates `### stats (anthropic/claude-opus-5-5)` etc.; `P$value` lists child values;
   `reviews$stats` is the child session (`$` falls through to children); `gptr_usage(reviews)` sums
   routes `api`, `api`, `plan-cli`; `subagent_start/end` drive the status line.
5. `gptr("Summarise this cohort", cohorts, parallel = 4)`: one inline child per element, 4 active,
   each reading `cohorts[["<name>"]]` in place (zero-copy [15 §2.3]); `summaries$<name>$text`.
6. At top level one block records the header and a `## <agent>: <first line>` note per child.

### 10.5 Example 7 — the script is the history

1. Recording (10.1 step 9): the block `# >>> gptr:7f3a21 model= date= prompt=<12 hex>` ... `# <<<
   gptr:7f3a21` (id from `cli::hash_sha256()` of time, pid and counter, never the RNG), written
   atomically (temp file + `file.rename`, md5 check, EOL/BOM preserved) or through
   `rstudioapi::modifyRange()` for a clean open buffer, cursor moved past the block [14 §4.3].
2. `source("analysis.R")`: `doc_locate()` finds the statement (validated srcref, else the `source()`
   frame inside `tryCatch`) and its block; the prompt hash matches, so `gptr()` returns at once with
   zero tokens and `source()` runs the recorded code as ordinary R.
3. `options(gptr.replay = "live")` under base `source()`/Rscript downgrades to replay with a warning
   (the old block is already parsed); `gptr_source(..., replay = "live")`, knitr and IDE line-by-line
   runs ask the model afresh, rewrite the block and skip the old code [14 §4.4.2].
4. The agent edits earlier code with `edit` on the document path (routed through the document
   backend, header `date`/`sha` refreshed); a user-edited block (sha mismatch) is protected.
5. Rmd/Quarto get a `gptr-<id>` chunk after the owning chunk (no `#>` lines); Jupyter gets an agent
   cell, written only when the notebook is not open.

### 10.6 Example 8 — artifacts are Shiny apps

1. `gptr("Build me an explorer ...", markers)`: `<attached name="markers">`; the model reads the
   `shiny-artifacts` SKILL.md (about 400 tokens, once).
2. It calls `r` with `app = r"(library(shiny); library(bslib) ... shinyApp(ui, server))"` and
   `gptr_tools$artifact(title = "marker-explorer", code = app, data = "markers")`; level 3 (process),
   so `manual` asks, showing the code.
3. `artifact()`: slug id with a `dir.create()` lock; `.gptr/artifacts/marker-explorer/v001/` with
   `app.R`, `R/gptr_data.R`, `data/markers.rds` (`saveRDS(compress = FALSE)`, size-capped); static
   checks (parses, ends with `shinyApp()`, no `setwd()`/installs/file reads).
4. `callr::r_bg(artifact_serve, list(dir, port_hint), package = "gptr", supervise = TRUE,
   cleanup_tree = TRUE)`; the child picks the port (never the parent's RNG [17 §4]) and publishes it
   by atomic rename; the parent polls, then checks HTTP 200 with curl; with chromote, a headless check
   returns errors and a screenshot attached to the `r` result. `artifact_start`; the viewer opens.
5. The result prints `artifact marker-explorer v1 -> http://127.0.0.1:4827 (running in background)`;
   the model reads the screenshot and may revise with `edits` (v002, same port); `gptr()` returns and
   the child keeps serving until `gptr_artifacts("marker-explorer", stop = TRUE)` or R exits.
6. `details$record_as` makes the block record `gptr_artifacts("marker-explorer", open = TRUE)` and
   `#> [app] .gptr/artifacts/marker-explorer/v001/app.R` instead of the app source.

### 10.7 Example 11 — a whole workflow that reads like R

First `source("workflow.R")` (interactive, consented workspace):

1. `prep = gptr(..., pbmc) |> gptr(...) |> gptr(...)`: one session, three turns (10.2); blocks
   `call=1..3` are written after the statement, safely, because `source()` parsed the file first
   [14 §2.1.3].
2. Plain R lines run; the next turn's `<workspace_changes>` shows `~ pbmc` from the snapshot diff.
3. The loop's `gptr(..., top, model = jev, choices = ...)` calls are System 1 inside control flow:
   per-element cache, one request per miss (about 350 ms), a `gptr_choice` compared with `==` (the
   `Ops` method returns a plain logical); nothing is written to the document.
4. For an unclear cluster, `"Cluster {cl} has ambiguous markers ({top}) ..."` is interpolated from the
   loop variables and runs live as a two-turn session; being nested, it gets no block; the JSONL store
   has the full record.
5. `gptr("Build a Shiny app ...", pbmc)`: the agent ships small summaries (UMAP coordinates, labels,
   top markers), not the 5 GB object; a block with the replayable `gptr_artifacts(...)` call follows.

Second run: `prep` replays (zero tokens; block code runs), System 1 calls hit the cache (same
branches, zero requests), nested investigations run live again (calls in loops are program, not
history; with `GPTR_REPLAY=replay` they error "not recorded", which is how CI proves a script makes
no model calls [14 §4.4.2]), and the artifact block re-opens the app. Under `Rscript` document writes
are deferred to process exit with a crash sidecar [14 §4.3].

---

## 11. Delivery

### 11.1 Milestones (each ends with `R CMD check --as-cran` passing on macOS, Linux and Windows CI)

| Milestone | Plans | Independently testable outcome |
|---|---|---|
| M1 Offline kernel | P01-P07 | With `gptr_fake_provider()`: the gateway dispatch table of 4.1, pipe continuation, running-session steering, fork, JSONL store and resume, 20-turn byte-prefix test, registry/loader/hook conformance, secrets grep test. No network. |
| M2 Live R agent and System 1 | P08-P11 | Evaluator torture suite and copy-safety suite; file tools against 11's oracles; provider conformance fixtures; north-star examples 2, 3, 4, 5 against the mock server and, opt-in, live APIs. |
| M3 Interactive, safe, recorded | P12-P15 | Permission decision matrix; REPL tests through a scripted line reader (UI backend `scripted`); document round trips (R, Rmd, qmd, ipynb); skills and templates; compaction tests; examples 1, 7, 10 (skills) and 12. |
| M4 Scale-out and interop | P16-P18 | MCP fixture server (both eras, OAuth mock); mixed inline/worker/CLI run with the fake CLI (INFRA-16/19 acceptance); examples 6, 9, 10 (MCP). |
| M5 Artifacts and release | P19-P20 | Artifact ladder on a fixture app; token benchmark within budgets; vignettes precomputed; examples 8 and 11; CRAN submission. |

### 11.2 Implementation plans (20, dependency order)

| Id | Title | Scope | R files owned | Depends on |
|---|---|---|---|---|
| P01 | Foundation | DESCRIPTION (Imports of section 8, R >= 4.2), NAMESPACE bootstrap, `.lintr`, `.Rbuildignore`, test setup, conditions, ids, text/truncation/spill, atomic raw I/O, token estimator, options, JSON encoding | `utils-conditions.R`, `utils-ids.R`, `utils-text.R`, `utils-fs.R`, `utils-tokens.R`, `utils-options.R`, `json-encode.R`, `zzz.R` | - |
| P02 | Secrets | vault and handles, `.env` parser and `gptr_env()`, aliases, redaction profiles and streaming hold-back, child environments | `auth-secrets.R`, `auth-dotenv.R`, `auth-redact.R` | P01 |
| P03 | Extension API | registry with 19 kinds and ranks, filters, `gptr_spec()`, `gptr_tool()`, `gptr_register()`, `gptr_registry()`, loader (factories, manifests, lazy activation, rollback), event bus and `gptr_on()`, `ctx`, `gptr_check()`, `gptr_api()` | `ext-registry.R`, `ext-loader.R`, `ext-hooks.R`, `ext-ctx.R`, `ext-check.R` | P01 |
| P04 | Reactor and transport | curl multi reactor with `processx::poll`, timers, admission, rate limiter, retry policy, SSE/NDJSON splitters, partial JSON, process helpers; base-R mock server test helper | `http-reactor.R`, `http-request.R`, `http-sse.R`, `http-process.R`, `json-partial.R` | P01, P02 |
| P05 | Model layer core | message model, projection, hand-off transform, usage/cost, catalog snapshot + resolver (+ `dev/` builder of `inst/extdata/models.json.gz`), provider records, fake provider | `provider-messages.R`, `provider-usage.R`, `catalog-models.R`, `provider-registry.R`, `provider-fake.R` | P03 |
| P06 | Session kernel | session object and methods, fork, store, request assembly with memo and prefix guard, agent loop state machine, dispatcher, `gptr_tools` object, `gptr_step()`, `gptr_sessions()`, `gptr_last()` | `session-object.R`, `session-store.R`, `session-request.R`, `agent-loop.R`, `agent-dispatch.R`, `agent-tools.R` | P03, P05 |
| P07 | Prompt, context and gateway | system prompt sections and presets, context blocks, `gptr()` dispatch and NSE, interpolation, `gptr_init()`, `gptr_config()`, built-in registration list | `prompt-sections.R`, `prompt-context.R`, `gptr-gateway.R`, `gptr-config.R`, `ext-builtins.R` | P06 |
| P08 | Evaluator and workspace | copy-safe evaluator, plots, guard, snapshot/diff/fingerprint, user-expression log, `gptr_describe()`, the `r` tool and `gptr_return()`; tracemem suite | `eval-run.R`, `eval-plots.R`, `eval-guard.R`, `env-snapshot.R`, `env-describe.R`, `tool-r.R` | P06, P07 |
| P09 | File, search and glue tools | read/write/edit with encodings and fuzzy fallback, diff engine, walker/gitignore/glob/grep/find/ls, `run`/`sh`/`py`/`sql` helpers | `tool-files.R`, `tool-diff.R`, `tool-search.R`, `tool-glue.R` | P06 |
| P10 | Native providers | adapters anthropic-messages, openai-responses, openai-completions (+ compat table), google-generative-ai; wire fixtures; conformance suite | `provider-anthropic.R`, `provider-openai.R`, `provider-completions.R`, `provider-gemini.R` | P04, P05 |
| P11 | System 1 | typed vectors and methods, TypeSafe adapter, vectorised fan-out, bounded rounds, S1 cache, opt-in emulation, gateway route | `s1-types.R`, `s1-client.R`, `s1-emulate.R` | P04, P05, P07 |
| P12 | Permissions and plan mode | risk classifier (levels, categories, paths, secret rules), policy with modes and rules, prompts, plan scratch environment and plan hand-off | `perm-classify.R`, `perm-policy.R` | P08, P09 |
| P13 | Console | UI backends, markdown stream renderer, status line, interrupt pause menu, REPL and slash commands, `ask` tool | `console-ui.R`, `console-render.R`, `console-interrupt.R`, `console-repl.R`, `tool-ask.R` | P12 |
| P14 | Documents and replay | locator, block grammar, atomic and IDE writes, deferred Rscript writes, R/Rmd/qmd/ipynb/transcript formats, replay modes, S2 cache, `gptr_source()`, `gptr_cache()` | `doc-locate.R`, `doc-blocks.R`, `doc-io.R`, `doc-formats.R`, `doc-replay.R` | P07, P08 |
| P15 | Skills, templates and compaction | skill discovery and catalog budget, activation, templates and commands, checkpoint compactor, budgets, cache TTL policy | `skill-catalog.R`, `prompt-templates.R`, `session-compact.R` | P07, P10 |
| P16 | MCP | client (stdio, HTTP, both eras, MRTR, cancel), config and imports, TOML subset, OAuth (PKCE, loopback/paste), `gptr_mcp()`, R closures in `gptr_tools` | `mcp-client.R`, `mcp-config.R`, `auth-oauth.R` | P04, P06, P09 |
| P17 | Sub-agents and parallel | inline/worker/cli backends, agent files, `gptr_agent()`, `agents =`, `parallel =`, `gptr_parallel()`, usage roll-up | `subagent-backends.R`, `subagent-parallel.R` | P06, P08, P10, P12 |
| P18 | CLI providers | claude CLI (stream-json, control protocol, in-process sdk MCP dispatcher, permission mapping), codex exec, fake CLI fixtures | `cli-claude.R`, `cli-codex.R` | P04, P16, P17 |
| P19 | Artifacts | shiny and html artifact types, snapshot, callr child, validation ladder, screenshots, `gptr_artifacts()`, `shiny-artifacts` skill | `artifact-shiny.R` | P08, P12 |
| P20 | Release | roxygen docs and examples (fake provider), precomputed vignettes, README/NEWS (1.0.0 breaking-change note), token benchmark (`dev/bench`, `test-bench-context.R`), Windows/Linux CI, R-devel copy-safety runs, cran-comments | none new (docs, tests, `dev/`) | all |

---

## 12. Risks, INFRA compliance and explicit deferrals

### 12.1 INFRA-01..INFRA-28 compliance [10a §14]

| Item | Status | Where |
|---|---|---|
| 01 own curl-multi transport, `pipewait = 0` | met | 6.2 |
| 02 normalised event protocol, failures as events | met | 5.4, 6.1 |
| 03 interrupt-safe streaming with steer/continue/abort | met in the console (pause menu via the resume restart); in programmatic calls abort persists, stores the partial and re-signals | `console-interrupt.R`, 4.1 |
| 04 honest partial and failed turns, projection | met | 5.2 |
| 05 connect, first-byte and idle timeouts, no total | met | 6.2 |
| 06 bounded retry with Retry-After cap | met | 6.2, 6.4 |
| 07 message model with provenance, byte-exact opaque data, images in tool results | met | 5.2, 5.3 |
| 08 hand-off transform | met | `provider-messages.R` |
| 09 argument validation; no execution after `length` | met | 6.4 |
| 10 never-throw dispatcher, source order, sequential `r` | met | 6.4 |
| 11 allow/deny/ask/modify hooks, modes, fail closed | met | 6.3, 6.7 |
| 12 own loop, steering after tool results, `max_turns`, stepwise API | met (`gptr_step()`) | 6.4 |
| 13 append-only JSONL v3 tree, RNG-free ids, crash-safe | met | 6.9 |
| 14 session object semantics, fork shares nothing | met | 4.3, 5.1 |
| 15 no package-global run state | met, with two documented execution-context pointers (`the$stack`, `the$last`) that hold no usage, queues or caches | section 2 |
| 16 one reactor for streams and children | met; the "background mode serviced by later" clause is deferred (v1.x) because `later` pumping in IDEs is unverified | 6.2 |
| 17 providers as data + closed set of wire adapters, exported versioned interface | met | 6.1, 13 |
| 18 System 1 as first-class typed, vectorised, abstention policy | met; argument names `min_confidence`/`uncertain` instead of `na_below`/`stop_below`, and a classed character instead of a factor for choices, for the reasons in D-06 | 6.14 |
| 19 subscription CLIs through processx, SIGINT then kill_tree, own session ids | met for `claude` and `codex exec`; Codex app-server is v1.x | 6.13 |
| 20 usage and cost by provider and route, TTL-split cache writes | met | 5.5 |
| 21 rate-limit awareness gating admission | met | 6.2 |
| 22 credentials never stored, redaction everywhere | met | 6.16 |
| 23 byte-level linear decoding | met | `http-sse.R` |
| 24 fake provider, mock server, fixtures, conformance | met | 3.3, 13.3 |
| 25 structured output coexisting with tools | met differently: a tool-using run hands back any R object with `gptr_return()`; JSON-schema output is used for System 1 emulation and available to plugins through adapters | 4.4, 6.14 |
| 26 loop-owned context management, one overflow retry | met | 6.4, 6.15 |
| 27 rendering decoupled from transport | met (the console is a plugin subscribing to events) | 2, 6.3 |
| 28 observability | opt-in redacted JSONL wire log in v1 (`options(gptr.wire_log = TRUE)`); OpenTelemetry spans v1.x | `http-reactor.R` |

### 12.2 Risks and mitigations

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| A CRAN reviewer objects to evaluating model code in the caller's environment or to document writes | medium / high | Every evaluation and write is user-initiated and consented (`gptr_init()`, interactive yes); examples use `gptr_fake_provider()` and `envir = new.env()`; precedents (btw, aisdk) and the policy text are cited in cran-comments [13 §1]. |
| Claude CLI route falls foul of Anthropic terms or name-use rules | medium / medium | Opt-in with a one-time notice, no credential handling, unmodified binary, provider can be disabled; maintainer asks Anthropic before release [07 §7]. |
| Provider API drift (betas for inline tools, mid-conversation system messages, thinking controls) | high / medium | Capabilities per model in the catalog with a cache-breaking fallback and a logged cost; wire fixtures; live suite before every release [G4 §7]. |
| MCP spec churn (two wire eras within a year) | high / medium | Thin protocol layer, fixtures per era, era cache [16 §7]. |
| Windows behaviour untested (processx `.cmd` shims, CTRL+BREAK, rename under locks, UTF-8) | high / high | Windows CI from P04 onwards; `.cmd` handled via `cmd.exe /d /c call`; atomic-write fallback; no free text on argv [13 §6, 16 §6]. |
| Interrupt menu does not work in RStudio/Positron/Jupyter | medium / medium | Documented support matrix; abort-only fallback when the resume restart is unavailable; manual test checklist in P13 [02 §7, 18 §7]. |
| Copy-safety regressions from R internals | medium / high | Fresh-process tracemem suite on R-release and R-devel; the leaf/by-name discipline; no binding locks; no large `mget()` snapshots [12 §7, P-A exp]. |
| Models use R-function tools (artifact, grep) less reliably than direct tools | medium / medium | Presets can promote any tool to direct; the north-star benchmark in P20 decides the default exposure per tool with measured success and token cost. |
| Token estimates are wrong for Claude and Gemini tokenizers | medium / low | Provider-reported usage dominates; the estimator errs high for tool output; thresholds keep a reserve [21 §2.8]. |
| Pure-R search is slow on huge trees or Windows | medium / low | Pruned walker, `grepRaw` prefilters, early exit at limits, files over 20 MB skipped with a notice; ripgrep accelerator is v1.x [21 §2.1]. |
| Plan hand-off surprises a user (a later call sees an earlier plan) | low / low | The console prints "using the plan from session <id>"; the `<plan>` block is visible in `/context`; `options(gptr.plan_handoff = FALSE)`. |
| `{name}` interpolation substitutes inside LaTeX or prose | low / low | Only bound names of short atomic vectors; `{{`/`}}` escapes; `options(gptr.interpolate = FALSE)`; the interpolated prompt is echoed at the console. |
| Inline sub-agents mutate reference objects (Seurat internals, data.table, environments) | medium / medium | Classifier flags reference mutation at level 2 (denied in parallel runs); documentation; `worker` backend for isolation [15 §7]. |
| A long R tool stalls other agents' streams | high / low | Streams buffer and resume; per-tool time limit; heavy compute goes to `worker` [15 §7]. |
| Self-maintained providers lag ellmer's breadth | medium / medium | Data-driven compat table covers most OpenAI-compatible hosts; plugins can add adapters [09 §4, 10a §16]. |
| Session files grow with images | medium / low | Images stored once per entry, spill files for long output, compaction checkpoints [02 §7]. |

### 12.3 Explicitly deferred beyond v1 (with the reason; none is a headline benefit)

| Deferred | Reason | Workaround in v1 |
|---|---|---|
| `background = TRUE` jobs serviced by `later` | IDE/Jupyter pumping unverified [15 §2.5] | `.run = FALSE` + `gptr_step()`; `gptr_parallel()` |
| In-session HTTP MCP server (`gptr_mcp_serve`) | needs httpuv + later pumping; 60 s client timeouts [07 verification] | claude CLI reaches the live session through the in-process `sdk` transport |
| Codex app-server driver with dynamic tools | experimental protocol, schema drift [08 §7] | `codex exec --json` |
| Sign in with ChatGPT (native plan auth) | preview API, eligibility (`invalid_client`) unverified, needs a live browser test [08] | `codex exec`; OpenAI API keys |
| knitr `{gptr}` engine | relaxes S-2; maintainer decision pending [14 §4.6] | `gptr("...")` in R chunks |
| `apply_patch` for GPT-5 family | unbenchmarked benefit [20 §7] | `edit` |
| `fork` backend, mirai/mori accelerators | GUI safety; mori saves transfer time only [15 §2.7-2.8] | `worker` (callr) |
| Session tree navigation (`/tree`, branch), Pi session import | not needed for the north star | `gptr_fork()`, resume by id |
| Claude plugin hooks import, `.codex/agents` TOML | trust and mapping work [16 §4.9, 20 §4.4] | skills, commands, agents and MCP from Claude plugins are consumed |
| Bedrock Converse/SigV4, Vertex, Azure AD, Copilot, Gemini Interactions | breadth, terms risk for Copilot [09 §7] | OpenAI-compatible endpoints (Bedrock's included) |
| Provider-native compaction plugins | betas [G4 §4.4.4] | checkpoint compactor |
| RPC mode, Shiny chat front end | not needed for north star; shinychat imports ellmer [17 §2.7] | `frontend` kind lets a package add one |
| `notebook_edit`, web search/fetch tools | opt-in extras [20 §4] | provider server-side search where available; `r` + curl |
| `/undo` of objects above 50 MB | would double memory and copy on the next edit [critic, P-A exp] | files and conversation are undone; the prompt warns first |
| ripgrep accelerator, OpenTelemetry spans | optional speed and observability | pure-R search; JSONL wire log |

---

## 13. Extensibility map (S-11)

### 13.1 One registry, 19 kinds, one verb

Every capability is a spec `list(kind, name, ...)` of class `c("gptr_<kind>", "gptr_spec")`,
validated by its kind, registered with one verb (`api$register(spec)` in a factory, `gptr_register()`
at top level, or a call argument at rank 0), resolved by rank (session 0 < project 1 < user 3 <
plugin 5 < built-in 6; ties: first wins with a diagnostic), filterable (`-builtin:permissions`,
`-tool:grep`, `-plugin:pkg`, `+...`; project filters cannot disable user or built-in policies and
hooks), and listed by `gptr_registry()` with a `tokens` column [G1 §3.1, §3.6].

| Category (S-11) | Kind and contract | Built-ins implemented on it | How an R package ships it | How a third-party agentic layer builds on it |
|---|---|---|---|---|
| Native API providers | `provider`: data record (id, api, base_url, auth resolver, models, compat, type `chat`) | `builtin:providers`: Anthropic, OpenAI, Google, OpenRouter, Groq, DeepSeek, Together, Ollama, LM Studio, vLLM, llama.cpp as data | factory in `extension.entry` registering records | a company gateway package registers its endpoint and auth resolver; agents use `model = "corp/model"` |
| Wire formats | `adapter`: `build`, `decoder` (or `classify`), `caps` (6.1) | anthropic-messages, openai-responses, openai-completions, google-generative-ai, fake | factory | a Bedrock Converse adapter package |
| Subscription CLI providers | `provider` type `cli` + adapter transport `process_jsonl` | cli-claude, cli-codex | factory | a plugin for another agent CLI (JSONL over stdio) |
| System 1 providers | `provider` type `classifier` + adapter `classify(build, parse)` | typesafe-system-one (TypeSafe, OpenRouter, Vercel records), emulation | factory | a local log-probability classifier package |
| Model routers | `router`: `route(request, ctx)` returns a model id; usable as `model = <router>`; errors fall back to the default | none built in (a Jev router is a vignette example) | factory | a routing layer that uses `ctx$decide()` to pick cheap vs strong models |
| Tools | `tool` (5.3): `execute(input, ctx)`, schema, exposure, execution, risk | read, write, edit, r, ask, grep, find, ls, run, sh, py, sql, artifact | factory, or `gptr(..., tools = list(gptr_tool(...)))` | domain tool packs reached as `gptr_tools$<name>()` |
| MCP servers | `mcp_server`: `mcpServers` entry + exposure, timeout | `builtin:mcp` (config, import, client) | `inst/gptr/mcp.json` | a plugin bundling servers, skills and tools (`plugins = clinical_trials`) |
| Skills | `skill`: Agent Skills directory | high-performance-r, shiny-artifacts | `inst/gptr/skills/<name>/SKILL.md` (also `inst/skills`), available when the package is attached | skills referenced by agent definitions |
| Prompt templates | `prompt`: Pi template grammar | review | `inst/gptr/prompts/<name>.md` | workflow commands (`/triage`) |
| Slash commands | `command`: `handler(args, ctx)` | the console commands | factory | `/panel`, `/review` of an orchestration package |
| Hooks and events | `hook`: `event`, `handler(event, ctx)`, `matcher`; session-scoped `gptr_on()` | builtin:store, builtin:documents, builtin:console renderer | factory | audit loggers, cost guards (`budget_exceeded`), CI gates |
| Permission policies | `policy`: `check(call, ctx)` -> allow/deny/ask/modify | builtin:permissions, builtin:plan | factory (user- or call-enabled; a project cannot disable user policies) | an organisation policy package (deny network sends, require review) |
| Context / environment describers | `context`: `provide(ctx, budget)`, placement `once`/`turn`; S3 `gptr_describe()` methods | environment, workspace, workspace_changes, attached, project instructions | `S3method(gptr::gptr_describe, <class>)` with gptr in Suggests (delayed registration); context factories | Bioconductor-aware describers (SingleCellExperiment, Seurat) |
| System prompt sections | `section`: stable text or `function(ctx)`, tier, order, budget | every built-in section (6.10) | factory | a domain preamble section |
| Compaction strategies | `compactor`: `should(session, ctx)`, `compact(session, ctx)` | builtin:compaction (checkpoint) | factory | provider-native compaction plugins |
| Document formats / history writers | `doc_format`: `locate`, `render`, `write` | r, rmd, qmd, ipynb, transcript | factory | a `targets` or Quarto-project writer |
| Artifact types | `artifact_type`: `build`, `check`, `launch`, `stop` | shiny, html | factory | a plumber-API or Quarto-dashboard artifact type |
| Sub-agent backends | `backend`: `start(spec, ctx)` -> handle with `fds`, `poll`, `cancel`; `capabilities` | inline, worker, cli | factory | a mirai or HPC-cluster backend |
| Agent definitions | `agent` (`gptr_agent()`), agent files | none shipped; files discovered | `inst/gptr/agents/<name>.md` | reviewer personas used by `agents =` |
| Front ends | `frontend`: `run(session, ...)` and a `ui` (`select`, `input`, `questions`, `notify`, `has_ui`) | console, none, scripted, rstudio | factory | a Shiny gadget or RPC front end |
| New categories | `kind`: `validate(spec)`, `resolve = "first" \| "all"` | - | factory | a plugin defines e.g. a `dataset_source` kind for its own sub-plugins |

### 13.2 Shipping plugins in R packages [G1 §4.4]

```text
DESCRIPTION   Imports: gptr (SDK users)  or  Suggests: gptr (describers, skills only)
              Config/gptr/plugin: true
              Config/gptr/api: >= 1.0, < 2
NAMESPACE     export(gptr_plugin)                      # the factory named in plugin.json
              S3method(gptr::gptr_describe, cohort)    # delayed registration
inst/gptr/plugin.json   {"name", "version", "gptr": {"api": ">= 1.0, < 2"},
                         "skills": "skills", "prompts": "prompts", "agents": "agents",
                         "mcpServers": "mcp.json",
                         "extension": {"entry": "pkg::gptr_plugin", "activation": "lazy",
                                       "provides": {"tool": ["trial_search"]},
                                       "declarations": {"trial_search": {"signature": "trial_search(condition)"}}}}
inst/gptr/skills/  inst/gptr/prompts/  inst/gptr/agents/  inst/gptr/mcp.json
```

Rules: discovery, not self-registration (no `.onLoad` calls into gptr); code runs only when the
plugin is enabled (call argument, user settings, or trusted project settings); declarative resources
of attached packages are available immediately; factories run lazily on first use of anything in
`provides`, and `declarations` put tool signatures in the frozen prompt before activation so lazy
loading never breaks the cache; a failing or version-incompatible factory is rolled back and
reported, never breaking gptr start-up.

```r
gptr_plugin = function(gptr) {
  gptr$require(">= 1.0, < 2")
  gptr$register(gptr::gptr_tool(
    name = "trial_search",
    description = "Search ClinicalTrials.gov for recruiting trials",
    parameters = list(type = "object", required = I("condition"),
                      properties = list(condition = list(type = "string"))),
    execute = function(input, ctx) search_trials(input$condition),
    exposure = "r",
    risk = function(input, ctx) list(level = 2L, categories = "network"),
    signature = "trial_search(condition)  # data frame of trials"))
  gptr$on("tool_result", function(event, ctx) NULL)
}
```

A third-party agentic layer needs only exported verbs:

```r
panel_review = function(file, models = c("opus", "gemini")) {
  runs = lapply(models, function(m) gptr::gptr(paste("Review", file, "for statistical errors"),
                                              model = m, .run = FALSE))
  names(runs) = models
  res = do.call(gptr::gptr_parallel, runs)              # concurrent, one reactor
  ok = gptr::gptr("Do these reviews agree that the analysis is sound?", res$text,
                  model = jev)                          # System 1 judge
  if (ok) res else res |> gptr::gptr("Reconcile the reviews into one list of fixes")
}
```

### 13.3 Conformance and API versioning policy [G1 §4.5]

- `gptr_api()$version` starts at `1.0`, independent of the package version. MINOR releases are
  additive (new kinds, events, ctx members, optional fields; handlers must ignore unknown payload
  fields). MAJOR releases break and require the CRAN notice period to reverse dependencies found with
  `tools::package_dependencies(reverse = TRUE, which = "most")`.
- Plugins negotiate features (`gptr$has("kind.router")`), not package versions. Requirements come
  from the manifest, `Config/gptr/api`, or `gptr$require()`; an unmet one disables that plugin only.
- Deprecation: an internal `gptr_deprecated()` warns once per session (class `gptr_deprecated`;
  `options(gptr.deprecations = "error")` for plugin CI); a deprecated member lives at least one MINOR
  release and six months.
- `gptr_check(x, error = FALSE)` runs the conformance suite: specs (fields, schema validity, a direct
  tool description at most 400 tokens, empty input handled), factories (every `provides` entry
  registered, no action at load time), packages (manifest, API requirement), adapters (fixture
  replay, error-as-event, chunk invariance), policies (the 18 §4.7 matrix). `gptr_fake_provider()`
  drives plugin tests offline.
- `gptr_reload()` is not exported in v1: plugin reload happens on `onUnload` hooks and a registry
  generation counter makes stale API objects error with `gptr_error_stale_api`.

---

## 14. Token-efficiency analysis (S-12)

All numbers are o200k estimates based on G4 §2.8 measurements, adjusted to this design's section
set; Claude's and Gemini's tokenizers are not public [21 §2.8].

### 14.1 Static prefix (system prompt + tool schemas) per preset

| Preset | Direct tools | T0 sections | Tool array | T1 (`r_env`) | Static total | Used for |
|---|---|---|---|---|---|---|
| `minimal` | read, write, edit, r | ~570 | 686 | 0 | **~1,260** | sub-agents, cheap models |
| `lean`, non-interactive (default) | read, write, edit, r | ~1,570 (with documents and system1) | 686 | ~400 | **~2,650** | scripts, knitr, Rscript |
| `lean`, interactive (default) | + ask | ~1,580 | ~910 | ~400 | **~2,890** | console |
| `full` | + grep, find, ls, artifact, agent | ~2,300 | ~2,300 | ~400 | **~5,000** | opt-in; models with a 4,096-token cache minimum |

Add about 70 tokens per visible skill, about 36 per R-function signature of MCP/plugin tools
(3,000-token cap), and the project instructions (about 150-600 for a typical vignette, 6,000 budget).
Reference points: G4's seven-direct-tool default is 3,598; Pi about 1,300; Claude Code 3-18K
[07 §1]; Codex 19-38K per turn [08]. After the first request the static prefix is read from cache at
0.05-0.1x input price.

### 14.2 Context blocks and tool results

| Item | Tokens | Budget |
|---|---|---|
| `<environment>` | ~70 | 100 |
| `<mode>` (manual / plan) | ~50 / ~120 | 150 |
| `<workspace>` (1 large object / 6 objects) | ~40 / ~120 | 600 |
| `<attached>` per object (`gptr_describe`) | 100-300 | 300 |
| `<workspace_changes>` (only when non-empty) | ~70 | 300 |
| `r` result: assignment with short console output | 30-80 | - |
| `r` result: `str()`/`head()` of a data frame | 150-300 | - |
| `r` result: error with traceback | 100-200 | - |
| plot image 768x512 | 532 | - |
| artifact screenshot (chromote) | ~1,080 | - |
| worst-case `r` output (20,000 chars at chars/2, then spill file) | ~10,000 | 8,000 chars past half the compaction threshold |
| System 1 request (per element, System 1 input tokens) | 250-450 | 32k-64k per request |

### 14.3 End to end: north-star example 1 (four requests)

| Request | Input | of which cache read | New (cache write) | Output (incl. thinking) |
|---|---|---|---|---|
| 1 (static 2,890 + first message 420) | 3,306 | 0 | 3,306 | 300 |
| 2 (+ assistant 300 + tool result 60) | 3,666 | 3,306 | 360 | 300 |
| 3 | 4,026 | 3,666 | 360 | 300 |
| 4 (final answer) | 4,406 | 4,026 | 380 | 450 |
| **Total** | **15,404** | **10,998** | **4,406** | **1,350** |

At Sonnet 5.5 prices with 1-hour writes (interactive tail TTL): writes 4,406 x $4/M = $0.018, reads
10,998 x $0.2/M = $0.002, output 1,350 x $10/M = $0.014: **about $0.03**. The same four requests
through the Codex CLI route would add 19-38K input tokens per turn [08]; a script-and-rerun harness
would also reload the 5 GB object for every fix. Example 4's twenty decisions cost about 6,000
System 1 tokens ($0.00025 at $0.042/M) against about 66,000 tokens ($0.13 uncached) for twenty
System 2 judgements.

### 14.4 Choices that save tokens

| Choice | Saving | Evidence |
|---|---|---|
| Four direct tools instead of seven | ~513 tokens per request | tool arrays 686 vs 1,199 [G4 §2.8] |
| `r` exposure for grep/find/ls/artifact/agent, MCP and plugin tools | ~290 tokens per tool per request (36 vs 328) | [G1 §2.5] |
| MCP as R signatures | 9 tools in 331 tokens; full schemas about 24x larger | [G4 §4.8, 16 §2.16] |
| Composition in one `r` call (filter tool results in R, print a summary) | 1,532 vs 109 tokens in G1's illustration; one round trip instead of several | [G1 §4.8] |
| Objects by name, budgeted descriptions | 300 per attached object; artifacts ship names, not inlined data (127k tokens avoided in 17's fixture) | [12 §3.5, 17 §2.9] |
| Shiny instead of HTML/JS for artifacts | 3.1-3.7x fewer output tokens | [17 §2.9] |
| Frozen system prompt, append-only transcript | avoids the 2.7x cost of rebuilding the prompt | [G4 §2.9] |
| No in-place micro-compaction; in-conversation checkpoint | avoids +32%; checkpoint 9.4x cheaper than a fresh summary | [G4 §2.9-2.10] |
| Diffs only when non-empty | ~70 tokens per changed turn, 0 otherwise | [G4 §4.8] |
| Plots at 768x512 | 532 vs ~900 tokens (1000x700) | [12 §3.5, 17 §3.3] |
| Output cap 20,000 chars + spill file | at most ~10k tokens per result (vs ~25k at Pi's 50 KB) | this design |
| Message-only edit results (diff only after a fuzzy match) | up to ~1k tokens per edit | [01 §2.1, 11 §4] |
| `minimal` preset for sub-agents | ~1,630 fewer static tokens per child request | [G4 §2.8] |
| System 1 for judgements | 100-500x cheaper per decision | [04 §2.5] |
| Redaction markers | 6-10 tokens instead of 26-104 per key | [G6 §1.11] |
| Compact skill catalog | 32% smaller than Pi's XML | [G4 §4.8] |

Choices that cost tokens, stated: the `r_session` R-function catalog (~250 tokens per request, bought
back by not declaring those tools directly); `ask` in interactive sessions (~220); project
instructions in every session (cached); `<r_env>` (~400, cached; prevents failed `library()` calls);
the Codex route (19-38K per turn, shown when selected); `full` preset (+~2,100).

### 14.5 Accounting, budgets and the benchmark suite

- **Estimator.** `context_tokens = provider usage of the last response + est_tokens(later entries)`
  with prose and code at chars/4, tool output at chars/2, CJK at 1 per character, images by the
  provider formula; chars/4 alone underestimates printed R output by about 51% [21 §2.8].
- **Accounting.** Every request is a usage row with route and TTL-split cache writes; `gptr_usage()`,
  `/cost`, `/context` (per-section and per-entry breakdown from the render memo) and the `tokens`
  column of `gptr_registry()` show where tokens go; `cache_break` events name the culprit of a
  broken prefix.
- **Budgets.** `budget = list(tokens, cost, turns)` per call or in config; per-kind budgets for
  sections (6.10), catalogs (skills `max(8000 chars, 1% of window)`, R signatures 3,000 tokens),
  context blocks (14.2) and hook-injected context (10,000 characters); `gptr_check()` flags
  violations; `budget_exceeded` stops a run at a turn boundary.
- **Benchmarks.** (a) `tests/testthat/test-bench-context.R` (offline, on CRAN): builds the first
  request of every preset and mode with the fake provider and asserts the estimates stay within
  budget (minimal <= 1,350; lean <= 3,000; full <= 5,200); (b) `dev/bench/tokens.R` (rtiktoken, not
  shipped): exact per-section counts, fails CI when the lean first request grows by more than 5%;
  (c) `dev/bench/northstar.R` (opt-in, live keys): runs north-star tasks 1-11 on small fixture data
  with fixed prompts and records input, output, cache reads and writes per task and route into
  `dev/bench/results/<version>.csv`, compared with the previous release; (d) the G4 cache simulator
  for layout changes.

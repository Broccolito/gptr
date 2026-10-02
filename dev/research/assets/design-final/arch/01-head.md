# gptr 1.0 — Architecture (definitive)

Status: final design, 2026-09-29. Author: lead architect (design phase).
Supersedes the three proposals in `dev/spec/proposals/`. Inputs, in order of authority:
`00-vision-brief.md` (REQ-nn), `01-decision-register.md` (S-n, D-nn), `02-north-star-examples.md` (NS-n),
`dev/plan/00-conventions.md`, the research reports `dev/research/NN-*.md` (their verification logs override
their bodies), the gap research G1-G7 and the three judge verdicts.

Citation conventions: `[NN §x]` is research report NN, section x. `[G3]` and `[G5]` are the two gap reports
that exist only as digest entries plus scratch prototypes (`00-digest.md` sections "G3" and "G5";
`scratchpad/work/G3/`, `scratchpad/work/G5/`). `[P-A §x]`, `[P-B §x]`, `[P-C §x]` are the proposals.
`[J-req]`, `[J-cran]`, `[J-impl]` are the three judges (requirements, CRAN/security, implementation).
`[final/x.R]` is a check run for this document with `Rscript --vanilla` in
`scratchpad/work/design/final/` (Appendix A). All code uses `=` for assignment and `|>` for pipes (S-9).

The companion documents are `05-plan-decomposition.md` (implementation plans P01-P26), the appended
"Final decisions" section of `01-decision-register.md`, and `dev/plan/00-conventions.md` (now free of
`[design]` markers). The interface contract (`04-interface-contract.md`, written next) fixes full behaviour
per exported function; this document fixes names, signatures, structures and mechanisms.

---

## 0. How this design was synthesised

**Base.** Two of three judges ranked P-A (lean R-native core) first; it has the best CRAN feasibility,
maintainability, incremental delivery (the whole S-8 contract runs offline on the fake provider before any
network adapter exists) and the smallest dependency closure. P-A is therefore the skeleton: its kernel,
layering, reactor, 7 Imports, milestone M1 and deferral discipline. The requirements judge ranked P-C first
for north-star ergonomics, pipe semantics and token efficiency; most of P-C's user-facing design is grafted
onto that skeleton. P-B contributes the mechanisms that keep "everything is a plugin" true over time.

**Grafts adopted** (each is traced in Appendix B):

| From | Graft | Where |
|---|---|---|
| P-C, G3 | `$value` designated by name (large objects), deep copy (small), boxed only when anonymous; replay block header `value=` instead of a `res$value = fit` line | §5.1, §6.9 |
| P-C, G5 | the classed-closure gateway namespace `gptr$...` as the single tools-as-functions dispatcher; `gptr$mcp$<server>$<tool>()`; the full polyglot bridge set (`sh`, `script`, `bg`, `jobs`, `out`, `py`, `sql`, `knit`) on G5's process engine | §4.2, §6.7 |
| P-C | every call shape returns a session (teams, fan-outs, children, replayed sessions are session kinds); pending plan hand-off for NS-12; `{identifier}` prompt interpolation; trimmed `ask` schema; describers for Seurat/SCE/dgCMatrix/data.table/Arrow/DBI; INFRA acceptance table; weak live-session index; risk table as data; evaluator shim when `gptr` is not attached | §4, §5, §6 |
| P-B | codetools layering test; one `builtin_<name>()` factory per built-in calling only the extension API; pure agent loop with an injected stream function; extra kinds (setting, secret_source, redaction_rule, env_alias, child_env, cache_policy, estimator, model); JSONL event-sink front end; `gptr_steer()/gptr_cancel()/gptr_wait()`; overlay fork default; CLI hygiene (version probe, billing-switch warning, neutral provider id `claude-cli`); ported Pi/report-02 oracles; quantitative reactor tests; `gptr_prompt()` | §2, §4, §11 |
| P-A | non-interactive `ask` stops the run with a classed `gptr_error_permission` (NS-12); explicit list of choices that cost tokens; offline CRAN-safe prefix-budget test; `tokens` column in `gptr_registry()`; System 1 on a piped session with `uncertain = function` escalation; milestone M1 | §6.8, §12 |
| G7 | copy-safe checkpoint pre-images (private-env bindings released with `rm()`, defused lists, `serialize(ascii = FALSE)`), `gptr_rewind()` as an appended branch-in-place entry | §6.16 |
| G2, G4 | gap-based tail TTL (not the adaptive rule); class-aware token estimator with an EWMA provider multiplier; `r` output cap about 4,000 tokens; read line numbers off; level-based describers at 150 tokens per object | §6.11, §12 |
| G6 + J-cran | vault and handles; one redactor at every sink; child processes get an empty `R_ENVIRON_USER`/`R_PROFILE_USER` (callr otherwise re-injects `~/.Renviron` keys); artifact and helper children get no provider keys | §6.5 |
| J-cran | hard rule: untrusted text is never a cli/glue format string; `gptr_trust()` separate from consent to write; first-use egress acknowledgement per provider; CI matrix incl. oldrel-4, no-suggests, `LC_ALL=C`, Windows | §6.3, §6.10, §9 |

**Fatal flaws fixed.** P-A: session held the designated value (fixed by the by-name policy); Codex could not
reach live R (fixed by the in-session HTTP MCP server, §8); no console pipe-steering of a running session
(fixed by experimental `background = TRUE`, §6.2); reactor re-entrancy unspecified (fixed by `allow_runs`,
§6.1); trust model underspecified (fixed by `gptr_trust()`, §6.10). P-B: `gptr_group` broke the one-object
rule (teams are sessions); Pi's 50 KB result cap (4,000-token cap); preview routes as defaults (SIWC and Codex
app-server deferred to v1.x); `processx::run()` and `.cmd` refusal (G5 engine). P-C: binding-lock guard on
inline sub-agents (removed; no binding locks anywhere); 1 GB `mget()` undo snapshots (G7 pre-images);
cassettes executing hidden code (not in v1; §1.3); `$<-` vs replay grammar (header `value=`); plan order that
could not pass M2 (P-A's M1-first order). All three: cli format-string injection and `~/.Renviron`
re-injection into workers (both fixed).

**Where this design departs from the judges, with evidence.**

1. *NSE capture (D-07).* All three judges recommended `rlang::enquo()`/`enquos()` (report 12 §2.D2). Gap
   report G3, which the judges did not weigh, showed that garbage rlang quosures keep a wrapper's frame alive,
   so `w = function(d) gptr("x", d)` makes the caller's object copy on its next in-place edit; base-R capture
   with G3's rules is copy-safe and also resolves forwarded dots correctly (G3 t2b, t5; verified by the G3
   fact-check, claims 6 and 8). I re-ran the decisive case independently: `rlang::enquos()` in the forwarding
   frame gives COPY, a base `...elt()` leaf gives "in place" `[final/capture_check.R]`. Decision: base-R
   capture under the copy-safety rules of §6.4; rlang stays an Import for weak references, object addresses
   and binding introspection.
2. *Weak references to frames.* G3 kept the live registry weak. I checked that a weak reference whose *key*
   is a function frame also makes the caller's argument sticky, as does a list that once held the frame, while
   an address string or an environment binding reset to `NULL` does not `[final/frame_hold_check.R]`. Rule R2
   of §6.4 follows: no frame is ever held in a list, closure, attribute or weak reference.
3. *Cassettes (nested-call replay).* J-req wanted them in v1; J-cran required HMAC binding and trust gating;
   J-impl wanted them deferred. v1 ships without cassettes: nested calls in loops run live on re-source (REQ-24
   allows model non-determinism), and `GPTR_REPLAY=replay` makes them fail with "not recorded" so CI can prove
   a script makes no model calls [14 §4.4.2]. Cassettes are specified as a v1.x plugin with J-cran's security
   rules and J-impl's content-fingerprint keys (§1.3).
4. *Background sessions.* J-cran and J-impl deferred `background = TRUE`; J-req wanted it. It ships in v1 as
   an explicitly **experimental**, opt-in feature (own plan, P22), because S-8 makes "pipe into a running
   session = steering" a core idea and G3 verified the mechanism end to end in terminal R (t3, t8, t9, p6).
   It is never used in examples or CRAN tests, needs `later` (Suggests), and documents an IDE support matrix.

---

## 1. Principles and scope

### 1.1 Pitch

gptr turns the R session into an agent harness and an R script into an agent program. `gptr()` is the only
gateway: with no prompt it opens a chat in the console; with a prompt it runs the agent and returns the agent
session itself, an environment with reference semantics that `|>` steers. System 1 calls (`model = jev`)
return typed R vectors that drop into `if`, `for` and `while`. The agent computes on the objects already in
memory through one model-visible R tool, and every other capability (search, shell and other languages, SQL,
MCP servers, Shiny apps, sub-agents) is an R function the model composes inside one evaluation. The script
the user works in is the harness and the history. Every capability, including every built-in, is a plugin
on one public, versioned extension API; and every design choice is judged by the tokens it costs.

### 1.2 Principles

| # | Principle | What it decides |
|---|---|---|
| P1 | **One gateway, one object** (S-1, S-8) | `gptr()` dispatches on its arguments and returns a `gptr_session` for every System 2 shape (chat, team, fan-out, child, replayed); System 1 returns typed vectors; there is no result list and no group class. |
| P2 | **Small kernel, everything else a plugin** (S-11) | The kernel is the reactor, message model, loop, dispatcher, evaluator, store and registry. Every feature a user sees is a `builtin:<name>` extension registered through the same public API a third party uses, replaceable or removable with a filter, and a codetools test keeps it that way. |
| P3 | **R is the compression layer** (S-12, REQ-42) | Four model-visible tools (`r`, `read`, `edit`, `write`) plus `ask` when a human is present. Everything else is an R function reached through `gptr$...` at about 36 tokens per signature instead of about 328 per direct tool [G1 §2.5], composed in one `r` call (22.9x fewer tokens than a bash tool on G5's 8 tasks). |
| P4 | **Objects stay in memory; the context holds names and budgets** (REQ-21/22) | Objects are referred to by name with budgeted descriptions (150 tokens per attached object, 600 for the workspace); data is never serialised into the context when R can compute a small answer. |
| P5 | **Copy-safety is an invariant** | gptr never holds a reference to a user object or a user function frame beyond an active run (rules R1-R10, §6.4); a fresh-process tracemem suite guards every entry point on R-release and R-devel. |
| P6 | **Own the wire, fail honestly** (S-10) | One gptr-owned reactor on curl multi handles and `processx::poll()`; failures are events, never conditions thrown through the loop; no httr2, no R LLM package. |
| P7 | **Append, never edit** | Transcript, JSONL store, caches and console transcripts are append-only; system prompt and tool array are frozen per session; compaction and rewind append entries. This keeps provider prompt caches warm and preserved thinking valid [07 §2.5, G4 §2.7]. |
| P8 | **Tokens are a measured budget** (S-12) | Every prompt section, context block, catalog and tool result has a budget; a calibrated estimator; per-request token ledger; an offline CRAN-safe budget test and a benchmark suite that fail on regressions. |
| P9 | **Consent before disk and network; trust before code** (REQ-02) | `.gptr/` only by `gptr_init()` or an interactive yes; writes only there, in `R_user_dir()` or `tempdir()`; first-use egress acknowledgement per provider; project-supplied executable configuration only after `gptr_trust()`. |
| P10 | **Fail closed** | A throwing policy denies; `tool_call`, `permission_request` and `document_write` hooks fail closed; an `ask` without a human stops the run with a classed error; untrusted text is never a format string. |
| P11 | **The script is the program and the record** (REQ-24-26, REQ-35) | Top-level calls own delimited blocks of recorded code; `gptr()` never executes a recorded block; orchestration is ordinary R control flow. |
| P12 | **Ship v1, defer explicitly** | Previews and experimental external protocols are v1.x plugins; nothing deferred is a headline benefit (§1.3). |

The three headline benefits map to the kernel: in-memory compute is the evaluator plus the copy-safety
invariant (P4, P5); System 1 + System 2 is one gateway with two adapter kinds on one reactor (P1, P6); the R
ecosystem is `gptr$...`, Shiny artifacts and runnable documents (P3, P11).

### 1.3 Scope of v1

**In v1.**

| Area | Content |
|---|---|
| Gateway and sessions | `gptr()` with every north-star call shape; session object with reference semantics; pipe steering (idle = follow-up, running = steer); explicit `gptr_fork()` (overlay workspace); SDK verbs; Pi-v3-shaped JSONL store with resume; experimental `background = TRUE` |
| Model access | Native adapters `anthropic-messages`, `openai-responses`, `openai-completions` (+ compat table for OpenRouter, Groq, DeepSeek, Mistral, Together, xAI, Cerebras, Fireworks, Ollama, LM Studio, llama.cpp, vLLM, Azure v1, Bedrock's OpenAI-compatible endpoint), `google-generative-ai`; `typesafe-system-one`; `cli-claude` (unmodified `claude` CLI); `cli-codex` (`codex exec --json`); `fake`; pruned models.dev catalog with prices |
| Tools | `r`, `read`, `edit` (accepts a pasted `*** Begin Patch` envelope), `write`, `ask`; namespace members `read/write/edit/grep/find/ls/help/search/describe/plot/out/sh/script/bg/jobs/py/sql/knit/app/mcp` |
| Safety | Modes plan/manual/edits/auto; advisory classifier (R, shell, SQL, Python); rules; critical and secret guards; checkpoints with `/undo`, `/redo`, `/rewind`; vault, handles, redaction at every sink |
| Documents | `.R`, `.Rmd`, `.qmd`, `.ipynb` blocks; replay modes; S1 and S2 caches; console transcripts; deferred Rscript writes |
| Ecosystem | Skills, prompt templates, slash commands, agent files (`.gptr`, `.claude`, `.codex`, `.pi`), plugin packages and directories, `.claude-plugin` bundles (skills, commands, agents, MCP); MCP client (both protocol eras, stdio and Streamable HTTP, OAuth); gptr as MCP server (in-process `sdk` transport for the claude CLI; loopback HTTP for Codex and external agents) |
| Agents | Inline, worker (callr) and CLI sub-agent backends; teams (`agents =`), fan-out (`parallel =`), `gptr_parallel()`, `gptr_map()` |
| Artifacts | Shiny apps in supervised background R processes with snapshots and a validation ladder |
| Front ends | Console REPL with pause menu; knitr `knit_print`; JSONL event sink; scripted UI for tests |
| Measurement | Usage and cost by route; token ledger; budgets; offline budget and prefix tests; token benchmark suite |

**Deferred to v1.x (with reason; each is a plugin on the v1 API).**

| Deferred | Reason | v1 workaround |
|---|---|---|
| Sign in with ChatGPT (native plan auth) | preview API; end-to-end sign-in never executed [08 digest]; J-cran, J-impl | `codex exec` route with live R through the in-session MCP server |
| Codex app-server driver (dynamic tools) | experimental protocol with schema drift [08 §7] | `codex exec --json` |
| Nested-call cassettes | executes code not visible in the script; shape-digest keys can replay stale code (J-cran, J-impl) | nested calls run live; `GPTR_REPLAY=replay` errors "not recorded" |
| `{gptr}` knitr chunk engine | relaxes S-2; maintainer decision pending [14 §4.6] | `gptr("...")` in R chunks with `knit_print` |
| `apply_patch` direct tool | benefit unbenchmarked [20 §7] | `edit` accepts patch envelopes |
| `fork` backend, mirai/mori accelerators | unsafe in GUIs; mori saves transfer time only [15 §2.7-2.8] | `worker` (callr) |
| Bedrock Converse/SigV4, Vertex, Gemini Interactions, Copilot | breadth; Copilot terms risk [09 §7] | OpenAI-compatible endpoints |
| Provider-native compaction and tool-result clearing | betas [G4 §4.4.4] | checkpoint compactor |
| Claude plugin hooks import, `.codex` TOML agents | trust and mapping work [16 §4.9] | skills, commands, agents and MCP from Claude plugins are consumed |
| File-inbox steering channel | injection path from shared folders [J-cran K-16] | pipe, pause menu, `gptr_steer()`, `ctx$send()` |
| RPC and Shiny chat front ends | not needed for the north star | `frontend` kind; JSONL sink |
| OpenTelemetry spans, ripgrep accelerator | optional | redacted JSONL wire log; pure-R search |

**Experimental in v1** (opt-in, documented, excluded from examples and CRAN tests): `background = TRUE`; the
Claude-plan route (policy status UNCERTAIN [07 §2.18], opt-in with a one-time notice).

---

## 2. Layers, modules and allowed dependencies

### 2.1 Layers

```text
 L6  GATEWAY        gptr() . gptr$ namespace (classed closure) . gptr_*() exports
                    capture (base R, copy-safe) -> identifier resolution -> route lookup in the registry
 -----------------------------------------------------------------------------------------------
 L5  FRONT ENDS     console REPL (pause menu, slash commands) . knit_print . JSONL event sink
                    UI backends (console, none, scripted, rstudio)          [frontend, ui kinds]
 ================================  public extension API  ======================================
 L4  CAPABILITIES   builtin:tools builtin:r builtin:ask builtin:bridges builtin:lang builtin:permissions
    (built-in       builtin:plan builtin:checkpoints builtin:skills builtin:prompts builtin:agents
     plugins)       builtin:mcp builtin:subagents builtin:cli builtin:system1 builtin:documents
                    builtin:artifacts builtin:workspace builtin:providers builtin:anthropic
                    builtin:openai builtin:openai-compat builtin:google builtin:secrets
                    services they may use: evaluator (eval-*), introspection (env-*), walker (tool-walk)
 -----------------------------------------------------------------------------------------------
 L3  SESSION        session object + live registry (weak) . JSONL store . fork/resume
     RUNTIME        run: recovery, overflow, compaction trigger, budgets, settle, nested runs
                    context assembly: frozen sections, first message, deltas, cache plan, prefix guard
 -----------------------------------------------------------------------------------------------
 L2  AGENT LOOP     pure state machine (Pi runLoop) with injected stream function . steer/follow-up
                    queues . tool dispatcher (validate -> gate -> execute; never throws; FIFO)
 -----------------------------------------------------------------------------------------------
 L1  MODEL ACCESS   message model + events + hand-off transform . provider records (data) . adapters
                    (anthropic-messages, openai-responses, openai-completions, google-generative-ai,
                    typesafe-system-one, cli-claude, cli-codex, fake) . catalog + prices . usage
 -----------------------------------------------------------------------------------------------
 L0  PLATFORM       registry + extension API + event bus + loader . reactor (curl multi +
                    processx::poll + timers + FIFO + admission) . process engine . secrets vault +
                    redactor . conditions . ids . encoding . JSON . schema . tokens . text budgets
```

Children polled by the reactor: callr workers, `claude`/`codex` CLIs, MCP stdio servers, `gptr$bg()` jobs.
Independent children: Shiny artifact apps (own event loop, parent-PID watchdog).

### 2.2 Allowed dependencies

| Layer (areas) | May call | Talks upward only through |
|---|---|---|
| L0 (`utils`, `json`, `ext`, `http`, `proc`, `auth`) | base R, Imports, L0 | return values; callbacks registered by upper layers |
| L1 (`provider`, `catalog`, `s1-types`) | L0 | INFRA-02 events via the `emit` callback |
| L2 (`agent-loop`, `agent-dispatch`) | L0, L1 types; the stream function, context builder and tool executor are injected | loop events |
| L3 (`session`, `agent-run`, `prompt`) | L0-L2; L4 only through registry lookups | agent events |
| L4 (built-in plugins: `tool`, `bridge`, `perm`, `ckpt`, `skill`, `mcp`, `subagent`, `cli`, `s1`, `doc`, `artifact`, `eval`, `env`) | the extension API (`gptr$register()`, `ctx`), L0, their own area, and the declared services `eval-*`, `env-*`, `tool-walk`, `proc-*` | tool results, events, spec contracts |
| L5 (`console`) | SDK verbs, extension API (`ui`, `frontend` kinds), L0 | printed output (the only printing layer) |
| L6 (`gptr-*`) | L0-L3, registry lookups by kind (never an L4 function by name) | return values |

Rules that keep this honest:

1. **L6 and L3 never call an L4 capability by function name.** They ask the registry
   (`registry_get("tool", "r")`, `registry_all("policy")`, `registry_route("classifier")`). This is what
   makes every built-in replaceable and testable with fakes (S-11) [P-C §2.2].
2. **Nothing below L5 prints.** Renderers subscribe to events (INFRA-27). Model, provider, tool and MCP text is
   rendered with `cli::cli_verbatim()` or passed as a `{x}` interpolation variable, never as a format string
   (§6.3, rule C1).
3. **Each built-in is one factory** `builtin_<name> = function(gptr) {...}` in the file named in §3.2. It
   receives the public API object and may call only that object, `ctx`, L0 helpers, its own area and the
   declared services. It is declared with `on_load(ext_declare_builtin("<name>", builtin_<name>))`, so later
   plans add built-ins in their own files without touching a shared list.
4. **Enforcement.** `tests/testthat/test-arch-layers.R` walks every namespace function with
   `codetools::findGlobals()` (codetools in Suggests; skipped without it), maps each internal callee to its
   file's area and layer, and fails when a call crosses a boundary not allowed by the table in
   `helper-arch.R` [P-B §2.4]. `builtin_*` factories are checked against rule 3.
5. **No package-global run state** (INFRA-15). The namespace holds only: the registry (configuration,
   generation counter), the catalog, the secret vault, the process reactor (connection pool, fd table, timers,
   and strong references to *active* runs until they settle), the artifact and job process tables (to stop
   children on unload), and weak indexes (live sessions, `gptr_last()`). Usage, queues, abort flags and every
   in-flight cache live in sessions and runs; `gptr_usage()` aggregates [G3 (2)].

### 2.3 Execution model

R is single-threaded; concurrency is cooperative. One **process reactor** owns every HTTP transfer and child
pipe; it runs only inside a blocking gptr call (`gptr()`, `gptr_wait()`, `gptr_step()`) or, for experimental
background sessions, from `later` callbacks while the console is idle. Each run is a state machine
(`queued -> requesting -> streaming -> tools -> boundary -> requesting | settled`). Tools that evaluate R or
touch files run one at a time from a FIFO on the main thread; while one runs, other agents' bytes buffer in
curl and are delivered within about 50 ms after it returns [15 §2.3].

**Re-entrancy.** Model-written code in `r` may call `gptr("task", data, model = m)` (a sub-agent) or MCP tools
over HTTP. The nested call re-enters `reactor_pump(until, allow_runs = <the nested run>)` on the same pool: it
advances all transfers but executes queued R tools **only** of the runs in `allow_runs`, so sibling agents'
R tools never run inside another tool's evaluation [J-impl, P-B §6.2, P-C §6.2]. Nested runs are children of
the running session (depth + 1, mode inherited and only tightened, usage rolled up, no document block).

### 2.4 One request, end to end

```text
gptr("Fit ...", mice)                                                                 (L6)
  capture dots with base-R leaves (no forcing of context objects); resolve identifiers
  route lookup: classifier model? team? fan-out? no prompt? document replay? -> registry
  new session: freeze preset, T0/T1 system blocks, tool array (once-serialised)             (L3)
  first user message: <project_instructions> <environment> <mode> <workspace> <attached> prompt
  run: loop step -> adapter$build(request) -> reactor transfer (pipewait = 0) -> SSE bytes
       -> byte splitter -> adapter normaliser -> INFRA-02 events -> renderer, store, usage   (L2/L1/L0)
  tool_call r{code} -> validate -> policies + tool_call hooks -> UI if ask -> FIFO             (L2/L4)
       -> evaluator in envir (capture, plots, snapshot diff, checkpoint pre-images) -> result
  steering drained after the complete tool-result message -> next request (cache prefix intact)
  settle: append entries (JSONL), document_write -> block below the call, return the session  (L6)
```

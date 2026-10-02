# P-B — gptr architecture proposal: a Pi-faithful layered runtime

Independent architecture proposal, design phase, 2026-09-29. Lens: mirror Pi's proven layered
architecture as closely as R allows, adapt only where R forces it or gptr's headline benefits demand it,
and optimise for robustness and reuse of Pi's battle-tested semantics.

Citation keys: `REQ-nn` (vision brief), `S-n`/`D-nn` (decision register), `NS-n` (north-star examples),
`CONV §n` (plan conventions), `[02 §2.2]` (research report and section, with each report's verification-log
corrections applied), `[pi: path:line]` (Pi clone, commit `1b347794`). Two experiments were run for this
proposal (`Rscript --vanilla`, R 4.4.3, one fresh process per case; scripts in
`scratchpad/work/design/P-B/`):

- **[PB-E1] copy safety.** After `lockBinding("x", e); unlockBinding("x", e)` the next `x[1] = 0`
  **copies the whole object** (`lockBinding()` marks the value immutable; with or without `gc()`). An
  `mget()` snapshot (kept or dropped) and a write to the same name inside an overlay
  `new.env(parent = e)` also make the next in-place edit copy. `bindingIsLocked()`, `ls()` name diffs,
  reads through an overlay, and leaf calls of `rlang::hash()`, `rlang::obj_address()`, 64 sampled values
  and `object.size()` leave the object editable in place. So report 15's binding-lock guard and report
  18's `mget()` undo snapshots must not touch user objects.
- **[PB-E2] token measurements** (o200k via rtiktoken in the private library, on G4's section builders):
  the default tool array (read, r, edit, write) is 686 tokens; the default system prompt 1,418 (static T0)
  + 1,013 (machine/project T1, fixture with 4 skills, 2 MCP servers, r_env); grep/find/ls cost 235/180/98
  as declared tools and 33/26/18 as R signatures; the artifact rules cost 688 as section + tool and 41 as
  a one-line pointer to a skill.

---

## 1. Pitch and design principles

**Pitch.** gptr is Pi transcribed into R and re-centred on the live R session. It keeps Pi's layers and
their seams where Pi has them: a unified provider API that turns every model (HTTP API, subscription CLI,
System 1 classifier) into one normalised event stream; a stateless agent loop with Pi's two nested loops,
steering and follow-up queues and never-throw tool pipeline; a session runtime that persists an
append-only Pi v3 JSONL tree, retries, recovers from overflow and compacts; harness features (tools,
skills, prompt templates, MCP, sub-agents, permissions, documents, artifacts) built as ordinary extensions
on one public, versioned extension API; and thin front ends (console, programmatic, JSON, knitr, SDK).
What changes is what R forces and what gptr is for. R is single-threaded, so the loop becomes a resumable
state machine driven by one reactor over curl and process file descriptors; R copies on modify, so events
are delta-only and handlers return patches; R interrupts are conditions with a `resume` restart, so
steering becomes a pause menu feeding one inbox. And gptr's purpose, an agent working in the user's
environment, replaces Pi's `bash` with an `r` tool and adds System 1 typed decisions, script-as-history
documents, Shiny artifacts and a session object that `|>` steers. Event names, stop reasons, the session
file, settings keys, extension verbs, the skill and template grammar and the tool error strings stay Pi's,
so Pi's documentation, examples and learned model behaviour transfer.

| # | Principle | How the lens applies it |
|---|---|---|
| P1 | Same layers, same seams as Pi | `ai_stream()` = pi-ai `stream()`; `agent_loop()` = pi-agent `runAgentLoop()`; `gptr_session` = `AgentSession`; the store = `SessionManager`; `builtin:*` extensions = coding-agent built-ins (section 2). A test enforces the layering (2.4). |
| P2 | Keep Pi's semantics and names where cheap | Event names and payloads, stop reasons, loop poll points [02 §2.2]; tool pipeline order and strings (`Tool <name> not found`, `Tool execution was blocked`, `Operation aborted`, `No result provided`) [pi: agent/src/agent-loop.ts:719,745]; retry lists (MIT, attributed) [02 §3.7]; session JSONL v3 [02 §2.11]; camelCase `settings.json` keys [05 §4.9]; extension verbs [05 §3.2]; Agent Skills catalog with read-tool activation; Pi's template grammar (67 tests ported) [05 §5.1]; read/write/edit/ls schemas byte-identical [01 §4.1]. |
| P3 | Adapt only where forced, and write each deviation down | The table below. |
| P4 | Robustness first | Never-throw seams; append-only persistence; fail-closed permissions; no package-global run state [10a INFRA-15]; copy-safety invariants [12 §2.C, PB-E1]; offline fixtures and a conformance suite for every provider, CLI and MCP path [10a INFRA-24]. |
| P5 | Everything is a plugin (S-11) | One `(kind, name)` registry [G1 §3.1]; every built-in is a `builtin:<name>` extension loaded through the `ext_load()` third parties use. |
| P6 | Token efficiency is a contract (S-12) | Every capability declares an exposure and a budget; tool array and system prompt frozen per session; context changes appended; tools, MCP tools and sub-agents callable from one `r` evaluation; token costs stated (section 14). |
| P7 | The live R session is the asset | Evaluate in the caller's environment; describe objects by name within budgets; never serialise large data; never hold references to user objects. |
| P8 | One object per conversation (S-8) | `gptr()` returns the session environment; the native pipe appends to it; forks are explicit. |

**Deviations from Pi.**

| Pi | gptr | Reason |
|---|---|---|
| Async event stream; parallel tools by default | Resumable loop state machine on one reactor; tools sequential, `concurrent` only for pure I/O | Single-threaded R; `r` mutates the live environment [02 §4.10, 15 §4.2] |
| `bash` tool | `r` tool; shell only through R helpers | S-4, REQ-09 |
| Cumulative `partial` on every event | Delta-only events, per-block closure buffers | Copy-on-modify cost ~2 s per 100 KB [02 §5.10, 19 §2.4] |
| Handlers mutate `event.input` | Handlers return patches | R value semantics [05 §4.1] |
| `AbortSignal` | Signal environment + interrupt `resume` restart (pause menu) | [02 §4.7, 18 §2.2] |
| `context_edit` entries for failed attempts | Projection only (still honoured when reading Pi files) | Append-only rule, preserved thinking [07, 10a INFRA-04] |
| `project_context` inside the system prompt | Project files as user-role data in the first user message | Repository text must not carry system authority; cache layout [G4 §4.2, 20 §4.5] |
| Summary request, `reserveTokens` 16384, keep-recent 20000 | In-conversation checkpoint; G4 threshold; keep-recent 0 | Cache economics, preserved thinking [G4 §2.9-2.10] |
| chars/4 estimator | chars/4 prose, chars/2 tool output, calibrated | chars/4 underestimates printed R output by 41-51 % [21 §2.8] |
| No turn limit | `max_turns` 50 | `gptr()` runs in loops and scripts [02 §4.11] |
| Provider retries 0 | 2 before any committed delta, then Pi's agent-level policy | INFRA-06 |
| rg/fd binaries, npm packages, QuickJS codemode | Pure-R search; R packages ship `inst/gptr/`; the `r` tool is the code mode | REQ-07; [05 §4.10, 06, G1 §4.8] |
| Anthropic subscription OAuth, legacy Codex backend | Unmodified CLIs; Sign in with ChatGPT | Vendor terms [03 §2.13, 07, 08] |
| Sessions in `~/.pi/agent/sessions` | `.gptr/sessions/` after consent, else `tempdir()` | CRAN [13 §2] |
| TUI shortcuts, renderers, widgets | Not ported | No R-console equivalent [05 §4.4] |

---

## 2. Architecture overview

### 2.1 Layers

```text
 +---------------------------------------------------------------------------------------+
 | L6 GATEWAY     gptr(...): quosure capture, NSE, dispatch on call shape, replay check,  |
 |                returns a session, a group or a typed System 1 vector                   |
 +---------------------------------------------------------------------------------------+
 | L5 FRONT ENDS  console REPL | print (programmatic) | jsonl sink | knit_print | SDK      |
 |                (Pi modes: interactive, print, json, [rpc deferred], sdk)               |
 +==================================  public extension API  ============================+
 | L4 HARNESS     builtin:tools builtin:r builtin:permissions builtin:plan builtin:skills |
 |  (built-in     builtin:prompt builtin:mcp builtin:subagents builtin:cli                |
 |   extensions)  builtin:system1 builtin:documents builtin:artifacts builtin:context     |
 |                builtin:compaction builtin:console builtin:secrets builtin:providers    |
 +---------------------------------------------------------------------------------------+
 | L3 SESSION     gptr_session (AgentSession) | Pi v3 JSONL store (SessionManager)        |
 |    RUNTIME     run with recovery: retry, overflow, compaction, settle | settings,      |
 |                resources, trust | context assembly, cache plan, prefix guard | inbox |  |
 |                usage and budgets | extension event dispatch                            |
 +---------------------------------------------------------------------------------------+
 | L2 AGENT       agent_loop state machine (Pi runLoop) | tool pipeline | queues |         |
 |                Pi-named events | abort signal and interrupt policy                     |
 +---------------------------------------------------------------------------------------+
 | L1 AI          ai_stream / ai_complete / ai_classify | adapters: anthropic-messages,   |
 |                openai-responses, openai-completions (+compat), google-generative-ai,   |
 |                typesafe-system-one, cli-claude, cli-codex, fake | message model,       |
 |                hand-off transform, partial JSON, validation, cost, catalogue, auth     |
 +---------------------------------------------------------------------------------------+
 | L0 KERNEL      reactor (curl multi + processx::poll + timers + pumps) | registry |     |
 |                secrets vault and redactor | json | ids | conditions | io | paths        |
 +---------------------------------------------------------------------------------------+
   children polled by the reactor: callr workers, claude/codex CLIs, MCP stdio servers
   independent children: Shiny artifact apps (own event loop, parent-PID watchdog)
```

| Layer | Pi counterpart | Responsibility | May depend on |
|---|---|---|---|
| L0 kernel | `ai/src/utils/*`, `core/{event-bus,exec,http-dispatcher}.ts` | reactor, registry, secrets, JSON, ids, I/O | nothing internal |
| L1 ai | `packages/ai` | one call = one normalised event stream ending in one assistant message; never throws | L0 |
| L2 agent | `packages/agent` (`agent-loop.ts`, `agent.ts`) | turns, tool calls, queues, abort; no files, settings or R | L0, L1 types; the stream function is injected |
| L3 session | `core/{agent-session,agent-session-runtime,session-manager,settings-manager,resource-loader,system-prompt}.ts`, `compaction/` | persistence, recovery, compaction, context assembly, event dispatch, settings, trust | L0-L2 |
| Extension API | `core/extensions/*` | the only door from L4 into L3 | L3 |
| L4 harness | `core/tools/*`, `src/extensions/*`, `skills.ts`, `prompt-templates.ts`, `packages/mcp` | every feature as a `builtin:<name>` extension plus private library files | extension API, L0, own area, declared services (`eval-*`, `env-*`, `tool-fs.R`) |
| L5 front ends | `src/modes/*` | render events, read input, own the interactive loop | SDK verbs, extension API (`ui`, `frontend`) |
| L6 gateway | `sdk.ts` + CLI parsing | `gptr()` | L3, L5, the System 1 front |

### 2.2 One turn, end to end

```text
gptr("prompt", x, model = opus)                                            (L6)
  capture dots as quosures; resolve identifiers; locate call in document; replay?
  session_prompt(s, input): input event -> templates/skills -> user message + context blocks   (L3)
  session_run(s) = run_with_recovery(agent_loop(state))                     (L3 -> L2)
    reactor_run(until = settled)                                            (L0)
      agent_step: poll inbox -> context handlers -> projection -> ai_stream (L2 -> L1)
        adapter$build -> curl handle (pipewait = 0) -> SSE bytes -> splitter -> adapter normaliser
        delta events -> agent reducer -> listeners: renderer, store (message_end), document, plugins
      agent_step: tool calls -> validate -> tool_call hooks -> policies -> ui -> execute (main-thread
                  FIFO) -> tool_result hooks -> steering placed after the tool-result message
    settle: overflow check -> retry check -> agent_settled
  return s (invisible if the answer was streamed)
```

### 2.3 State ownership

Run state lives in the session (transcript mirror, inbox, signal, usage, listeners), its agent state and the
reactor of the running top-level call. Package-level environments hold only the registry (with a
generation counter), the catalogue, MCP connections (for the R session's lifetime), the vault and weak
indexes (`gptr_jobs()`, `gptr_last()`); `gptr_usage()` aggregates live sessions and store files
[10a INFRA-15].

### 2.4 Enforcing the layering

`tests/testthat/test-arch-layers.R` walks every namespace function, lists the internal functions it calls
with `codetools::findGlobals()` (Suggests), maps both to their file's area and fails when a call crosses a
boundary not allowed in `tests/testthat/helper-arch.R` (for L4: extension API + own area + declared
services). Pi's package boundaries become a test, which keeps "everything is a plugin" true as code grows.

---

## 3. Package file layout

Naming follows `CONV §3` (`R/<area>-<topic>.R`); the conventions' area list is confirmed unchanged
(compaction and context assembly live in `session`, sections and context blocks in `prompt`, the reactor
in `http`). A `*-builtin.R` file holds exactly one `builtin:<name>` factory and only calls the extension
API (P5).

| Area [layer] | Files and one-line responsibilities |
|---|---|
| utils [L0] | `utils-conditions.R` `gptr_abort/warn/inform()`, `resignal_interrupt()` · `utils-ids.R` RNG-free entry/session/block ids · `utils-encoding.R` UTF-8 marking, ASCII JSON for pipes · `utils-paths.R` project root, user dirs, workspace guard · `utils-io.R` binary and atomic writes, JSONL appends inside `suspendInterrupts()`, `dir.create()` locks · `utils-truncate.R` head/tail truncation, spill files · `utils-tokens.R` calibrated estimator · `utils-hash.R` sha256, canonical JSON · `utils-options.R` documented `gptr.*` options · `utils-interactive.R` mockable `gptr_has_ui()` |
| json [L0] | `json-encode.R` `json_encode()`, once-serialised entries, bodies by concatenation [19 §2.2] · `json-partial.R` incremental partial-JSON scanner [03 §5.2] · `json-schema.R` validation and Pi-style coercion |
| http [L0] | `http-reactor.R` curl multi pool + process table + timers + pumps + tool FIFO · `http-request.R` request spec -> curl handle, connect/first-byte/idle timeouts · `http-sse.R` vectorised byte SSE splitter [21 §2.6] · `http-ndjson.R` pipe line splitter · `http-retry.R` Pi's provider-retry rules, RNG-free jitter · `http-ratelimit.R` per-provider limiter · `http-process.R` processx wrapper (write-all, UTF-8, tree kill, `.cmd` refusal) |
| ext [L0/L3] | `ext-registry.R` `(kind, name)` registry, ranks, filters, diagnostics · `ext-kinds.R` kind table and validators · `ext-specs.R` the 22 spec constructors and `gptr_spec()` · `ext-api.R` the `gptr` API object · `ext-ctx.R` the `ctx` object · `ext-events.R` catalogue and dispatch semantics · `ext-load.R` transactional/lazy factories, plugin packages, `.claude-plugin` · `ext-version.R` API version and deprecation · `ext-check.R` conformance |
| auth [L0/L1] | `auth-secrets.R` vault and handles · `auth-redact.R` redactor incl. streaming hold-back · `auth-dotenv.R` `.env` parser and aliases · `auth-store.R` `auth.json` (0600, locked) · `auth-resolve.R` resolution order, origin binding · `auth-oauth.R` PKCE, loopback/paste/device · `auth-siwc.R` Sign in with ChatGPT · `auth-childenv.R` child environments · `auth-builtin.R` `builtin:secrets` |
| provider [L1] | `provider-types.R` messages, blocks, usage · `provider-events.R` normalised events, closure-buffer accumulator · `provider-adapter.R` adapter contract and fixture runner · `provider-stream.R` `ai_stream/ai_complete()` · `provider-transform.R` hand-off and projection · `provider-overflow.R` Pi's patterns (MIT) · `provider-thinking.R` level clamping · `provider-cost.R` tiers, 5 min/1 h writes · `provider-anthropic.R`, `provider-openai-responses.R`, `provider-openai-completions.R`, `provider-openai-compat.R`, `provider-google.R` adapters · `provider-fake.R` fake provider · `provider-builtin.R` `builtin:providers` |
| catalog [L1] | `catalog-load.R` snapshot + cache + overrides merge · `catalog-resolve.R` references and aliases · `catalog-refresh.R` explicit ETag refresh |
| agent [L2] | `agent-state.R` Pi `Agent` state and reducer · `agent-loop.R` runLoop as a state machine · `agent-tools.R` tool pipeline · `agent-signal.R` abort and interrupt policy · `agent-events.R` Pi event constructors |
| session [L3] | `session-object.R` `gptr_session` and methods · `session-runtime.R` prompt, run with recovery, settle · `session-store.R` Pi v3 JSONL tree · `session-convert.R` snake_case <-> camelCase · `session-context.R` request assembly · `session-cache.R` cache plans, prefix guard · `session-compact.R` checkpoint compaction · `session-inbox.R` steering inbox · `session-settings.R` settings merge, `gptr_config()` · `session-resources.R` resource loader · `session-trust.R` project trust · `session-workspace.R` `gptr_init()`, egress ack · `session-usage.R` usage, budgets · `session-fork.R` fork/resume/list · `session-background.R` `later`-serviced sessions |
| prompt [L3/L4] | `prompt-sections.R` section registry, presets, patches · `prompt-builtin.R` static section texts · `prompt-blocks.R` context-block renderers · `prompt-instructions.R` AGENTS.md/CLAUDE.md/vignette discovery · `prompt-templates.R` Pi template grammar |
| tool [L4] | `tool-spec.R` `gptr_tool_result()` · `tool-functions.R` `gptr_tools` dispatcher, signatures, BM25 search · `tool-fs.R` walker, gitignore, globs · `tool-read.R`, `tool-write.R`, `tool-edit.R`, `tool-diff.R`, `tool-patch.R`, `tool-grep.R`, `tool-find.R`, `tool-ls.R`, `tool-ask.R` tools · `tool-glue.R` `run/sh/py/sql/engine` helpers · `tool-builtin.R` `builtin:tools` |
| eval, env [L4 services] | `eval-core.R` hand-rolled evaluator · `eval-plots.R` capture and PNG · `eval-guard.R` static lists · `eval-format.R` model text · `eval-builtin.R` `builtin:r` (the `r` tool) · `env-snapshot.R` copy-safe snapshot/diff · `env-describe.R` `gptr_describe()` · `env-history.R` task-callback log · `env-packages.R` capability probe, `<r_env>` · `env-builtin.R` `builtin:context` |
| perm [L4] | `perm-classify.R` advisory risk classifier + secret rules · `perm-rules.R` rule grammar · `perm-gate.R` mode x risk table, prompts · `perm-builtin.R` `builtin:permissions`, `builtin:plan` |
| skill [L4] | `skill-discover.R`, `skill-frontmatter.R`, `skill-catalog.R`, `skill-builtin.R` discovery, lenient YAML, budgeted catalog, activation |
| mcp [L4] | `mcp-config.R` config and imports · `mcp-toml.R` Codex TOML · `mcp-client.R` connection, eras, MRTR · `mcp-stdio.R`, `mcp-http.R` transports on the reactor · `mcp-oauth.R` · `mcp-exposure.R` closures, signatures · `mcp-server.R` gptr as server · `mcp-builtin.R` `builtin:mcp` |
| subagent [L4] | `subagent-backend.R` contract, `auto`, limits · `subagent-inline.R` · `subagent-worker.R` + `subagent-worker-main.R` callr backend and child entry · `subagent-defs.R` agent files · `subagent-group.R` groups, `gptr_parallel/map()` · `subagent-builtin.R` |
| cli [L1/L4] | `cli-common.R` detection, isolation flags, consent · `cli-claude.R` stream-json + control protocol + `sdk` MCP · `cli-codex.R` app-server + exec fallback · `cli-builtin.R` |
| s1 [L1/L4] | `s1-adapter.R` `typesafe-system-one` · `s1-emulate.R` opt-in emulation · `s1-types.R` typed vectors · `s1-vctrs.R` · `s1-call.R` vectorised front · `s1-cache.R` · `s1-builtin.R` |
| doc [L4] | `doc-locate.R`, `doc-scan.R`, `doc-blocks.R`, `doc-io.R`, `doc-rmd.R`, `doc-ipynb.R`, `doc-ide.R`, `doc-backend.R`, `doc-replay.R`, `doc-transcript.R` report 14's components [14 §4.1] · `doc-builtin.R` `builtin:documents` |
| artifact [L4] | `artifact-store.R` ids, versions, snapshots · `artifact-run.R` callr / in-process / fork runners · `artifact-check.R` validation ladder · `artifact-child.R` port file, watchdog · `artifact-builtin.R` |
| console [L5] | `console-repl.R`, `console-reader.R`, `console-render.R` (streaming markdown), `console-commands.R`, `console-ui.R` (`gptr_ui` backends), `console-menu.R` (pause menu), `console-jsonl.R` (Pi-named JSON events), `console-knitr.R`, `console-builtin.R` |
| gptr [L6] | `gptr-gateway.R` dispatch · `gptr-nse.R` identifiers, prompt selection · `gptr-interpolate.R` `{symbol}` interpolation · `gptr-values.R` `gptr_return/last/prob()` · `zzz.R` lazy S3 registration, `.onUnload` cleanup |

**inst/**: `extdata/models.json.gz` (pruned models.dev snapshot with prices, MIT) [09 §4.7];
`gptr/plugin.json` (the built-in manifest); `gptr/skills/{high-performance-r, shiny-artifacts,
gptr-tools}`; `gptr/prompts/{review, explain, tidy}.md`; `gptr/agents/{reviewer, planner}.md`;
`gptr/templates/{vignette.Rmd, gitignore}`; `COPYRIGHTS` (Pi MIT for ported strings, schemas and pattern
lists; models.dev MIT; ideas credited per [10a §15]).

**tests/**: one `test-<area>-<topic>.R` per R file; helpers `helper-fake-provider.R`,
`helper-mock-server.R` (base-R SSE mock in callr, `skip_on_cran()`) [15 §5.1], `helper-fake-cli.R`
[07 §5.9], `helper-mcp-server.R` (pure-R, both eras) [16 §5.2], `helper-arch.R` (layer rules), `setup.R`
(redirect `R_USER_*_DIR`, blank keys, non-interactive options) [13 §4]; `fixtures/` with wire fixtures per
adapter, Pi v3 sessions, documents (incl. Python-written notebook floats), MCP transcripts, Codex's 25
apply-patch fixtures. Suites: adapter conformance (INFRA-24d), fresh-process copy safety (incl. PB-E1),
20-turn prefix stability [G4 §4.9], secrets end-to-end grep [G6], layer dependencies. `dev/bench/`
(not shipped): token benchmark, cache simulator, grep/read/SSE benchmarks [21].

---

## 4. Exported API

### 4.1 The gateway

```r
gptr = function(..., prompt = NULL, model = NULL, mode = NULL, preset = NULL, tools = NULL,
                skills = NULL, extensions = NULL, plugins = NULL, agents = NULL, parallel = NULL,
                choices = NULL, levels = NULL, na_below = NULL, stop_below = NULL,
                thinking = NULL, system = NULL, max_turns = NULL, budget = NULL,
                background = FALSE, context = NULL, record = NULL, replay = NULL,
                envir = parent.frame(), .run = TRUE, .stdin = FALSE)
```

All options follow `...`, so R matches them only by exact name: a context object named `mod` can never be
swallowed by `model` (the partial-matching trap of [05 §4.1]).

**Capture.** `rlang::enquos(...)` for the dots, `rlang::enquo()` for identifier arguments. Context objects
stay quosures inspected by name through leaf functions, never forced into `gptr()`'s frame, so every object
stays editable in place [12 §2.D2, §5.4]. Calls among the dots (including the inner `gptr()` of a pipe) are
evaluated once; their values are fresh.

**Dispatch** (first matching rule wins):

| # | Call shape | Result |
|---|---|---|
| 1 | nothing | interactive console session; returns the session invisibly on `/exit`; non-interactive: `gptr_error_noninteractive` unless `.stdin = TRUE` [18 §4.2] |
| 2 | first dot is a `gptr_session`, no prompt | interactive: console on that session; otherwise returns it |
| 3 | first dot is a `gptr_session` + prompt | **the same object is steered** (S-8): running -> the prompt is queued as a steering message and the call returns at once; idle -> a follow-up turn runs to settlement; returns the same environment |
| 4 | first dot is a `gptr_group` + prompt | fan-in: new session with each member's final text as context |
| 5 | `model` resolves to a classifier provider | System 1: vectorised typed decision (5.6); a session argument is an error |
| 6 | `agents = list(...)` | one sub-session per agent, run concurrently; returns a `gptr_group` |
| 7 | `parallel = n` + one list/vector/data-frame context | map over elements (rows), `n` at a time; `gptr_group` |
| 8 | anything else with a prompt | new session (a linked child session when called from model-written code during a tool call) and run |

Rules 3-8 first pass the document check (`builtin:documents`; a pipeline's k-th call owns the block with `call=k`): the call is located in its document
[14 §4.2]; a fresh recorded block under replay returns a *replayed* session at once (zero tokens, answer
from the S2 cache when present, conversation from the session file named in the block header), and the
document's own code runs next as ordinary R [14 §4.4]. System 1 consults its cache instead.

**Prompt selection** [12 §2.D3]: `prompt =`; else the first unnamed string literal; else the first
unnamed length-1 character value (a variable, `glue::glue()`); the rest is context. Two unnamed literals
warn. `purrr::map(x, gptr, "q")` is indistinguishable from literals, so mapping must name the prompt (or use
`gptr_map()`).

**Light interpolation** (makes NS-11 work as written): in a *string literal* prompt, `{name}` with `name` a
syntactic symbol bound in `envir` to an atomic vector is replaced by its value (collapsed with ", ", cut at
1,000 characters). Unbound names, non-symbols (`{x + 1}`, `{"a": 1}`) and `{{ }}` stay verbatim; variables
and `glue` objects are never re-interpolated; `options(gptr.interpolate = FALSE)` turns it off. Report 12
advised against auto-interpolation [12 §2.D4]; restricting it to bare bound symbols in literals keeps code,
JSON and most LaTeX untouched. The document keeps the literal template.

**Identifier resolution** for `model`, `mode`, `preset`, `tools`, `skills`, `extensions`, `plugins`,
`thinking`, `agents` [12 §3.11, amended D-07]:

```text
string                  -> itself
symbol s, s is a known name (alias, provider, router, mode, preset, skill, extension, plugin)
                        -> "s"; like library(), it wins over a same-named variable (one-time message)
symbol s bound in envir -> its value if character or a gptr spec, else an error naming the class
symbol s otherwise      -> "s" (validated later, with adist() suggestions)
!!x                     -> the value of x (explicit escape, handled at capture)
c(...) / list(...)      -> element-wise; +name / -name modifiers kept (tools, skills, extensions)
other calls             -> evaluated in an alias mask (if (hard) opus else haiku); in agents = the
                           mask also binds agent = gptr_agent
```

Model references containing a decimal are echoed (`gpt-5.10` parses as `gpt-5.1`), and documents always
receive quoted canonical ids [09 §4.9].

**Return.** A `gptr_session` (rules 1-3, 8), a `gptr_group` (4, 6, 7) or a typed System 1 vector (5);
sessions are invisible when the answer was streamed, visible otherwise [18 §4.5]. `.run = FALSE` returns
the session with the prompt queued (SDK); `background = TRUE` returns the running session and services it
from `later` while the console is idle (6.9). Other arguments: `mode` (`plan`/`manual`/`edits`/`auto`),
`preset` (section 9), `tools` (`+`/`-` over the preset), `skills` (preload as `<skill_content>`; `FALSE`
disables the catalog), `extensions`/`plugins` (enable code for this session, rank 0), `system` (replaces
preamble, tools and rules: Pi's custom prompt), `budget = list(tokens, cost, turns, seconds)`, `context`
(`auto`/`summary`/`names`/`none`), `record`/`replay` [14 §4.4.2], `envir` (default the caller's frame,
with the magrittr mask fix [12 §2.B4]).

### 4.2 The other 77 exports

All names are `gptr_*` (D-28): G1's collision-checked set [G1 §4.7] plus `gptr_redact()` and
`gptr_prompt()`. Formals that forward user arguments are dot-prefixed.

**Setup and status**

- `gptr_init(path = ".", quiet = FALSE)`: creates `.gptr/` (vignette.Rmd, settings with `record = "auto"`,
  `.gitignore`) and adds `^\.gptr$` to `.Rbuildignore` in packages; an explicit `path` is consent, a
  missing one asks interactively and errors otherwise [13 §4].
- `gptr_config(..., .scope = c("project", "user", "session"), .reset = NULL)`: no arguments returns the
  effective settings; named arguments (bare identifiers allowed: `model = sonnet, mode = manual`) write
  only those keys, mapped to Pi's camelCase; project scope may only tighten security.
- `gptr_env(path = ".env", aliases = NULL, set_env = TRUE, override = FALSE, quiet = FALSE)`: own `.env`
  parser, alias mapping (`jev-key` -> `TYPESAFE_API_KEY`), registers values with the redactor, exports
  canonical names only, never prints values [G6 §4].
- `gptr_login(provider, method = c("auto", "oauth", "key", "device"))` / `gptr_logout(provider)`:
  OpenRouter PKCE, Sign in with ChatGPT, MCP servers (`"mcp:<name>"`) or a masked key prompt, stored in
  `auth.json`; logout removes and, where possible, revokes.
- `gptr_providers(check = FALSE)`: providers, types, credential sources (names and fingerprints only),
  plan-usage status of CLI providers, egress acknowledgement; `check` pings.
- `gptr_models(query = NULL, provider = NULL, refresh = FALSE, reset = FALSE, discover = FALSE)`: searches
  the merged catalogue; `refresh` = explicit ETag download; `discover` = local `/v1/models` [09 §4].
- `gptr_trust(path = ".", decision = c("trust", "distrust", "forget"))`: project trust decision.
- `gptr_skills(cwd = getwd(), refresh = FALSE)`, `gptr_agents(scope = c("all", "project", "user"))`,
  `gptr_plugins(installed = FALSE)`: discovery listings (plugins: one vectorised `dir.exists()` over
  installed packages [G1 §4.4]).
- `gptr_mcp(server = NULL, tools = FALSE, refresh = FALSE)`: servers (own and imported), era, state,
  exposure, tools with signatures.
- `gptr_mcp_add(name, command = NULL, args = character(), env = NULL, url = NULL, headers = NULL,
  scope = c("user", "project"), exposure = "r", timeout = 60)`, `gptr_mcp_remove(name, scope)`,
  `gptr_mcp_import(from = c("claude-code", "claude-desktop", "codex", "cursor", "vscode", "pi", "gemini"),
  names = NULL, scope = "user")`: edit gptr's `mcp.json` only [16 §4.4].
- `gptr_mcp_serve(tools = c("r", "r_objects", "r_plot"), envir = parent.frame(), port = NULL,
  host = "127.0.0.1", print_config = interactive())` / `gptr_mcp_stop(server = NULL)`: serve the live
  session over Streamable HTTP (bearer token, Origin check, permission gate), print client configs
  [16 §4.6].

**Documents, artifacts, safety**

- `gptr_doc(path = NULL, format = NULL, blocks = FALSE)`: get/set/disable (`FALSE`) the recording target;
  `blocks = TRUE` lists blocks with status fresh/stale/edited/orphan.
- `gptr_source(file, replay = getOption("gptr.replay", "auto"), envir = parent.frame(), echo = FALSE)`:
  block-aware sourcing that can regenerate stale blocks without running the old code [14 §4.4.2].
- `gptr_cache(action = c("info", "prune", "clear"), kind = c("s1", "s2", "tmp"), older_than = NULL)`.
- `gptr_artifacts(running = FALSE)`, `gptr_artifact_open(id, version = NULL, view = interactive())`,
  `gptr_artifact_stop(id = NULL)`, `gptr_artifact_export(id, path, format = c("dir", "shinylive"))`:
  registry, (re)start and view (also the replayable line written into documents), stop, export [17 §4].
- `gptr_permissions(rule = NULL, action = c("show", "allow", "ask", "deny", "remove"),
  scope = c("session", "project", "user"), session = NULL)`: rules such as `write(results/**)`,
  `r(fn:write.csv)`, `r(level<=1)` [18 §3.7].
- `gptr_risk(code, envir = parent.frame(), root = NULL)`: the advisory static classifier; never evaluates.
- `gptr_redact(x, profile = c("persist", "stream", "context", "code", "user_data"))`: the session redactor.

**Values and introspection**

- `gptr_usage(x = NULL, by = c("model", "route", "session", "agent"))`: usage and cost (children
  included); `NULL` aggregates live sessions and the project's session files.
- `gptr_last()`: last session, group or aborted partial of this R process.
- `gptr_describe(x, budget = 300L, ...)`: S3 generic for the compact description the model sees
  [12 §3.9].
- `gptr_return(value)`: used by agent code inside `r`; sets the session's `$value` without copying.
- `gptr_prob(x, what = c("prob", "confidence"))`: probabilities of a System 1 result.
- `gptr_packages(refresh = FALSE, probe = FALSE)`: installed fast packages without loading them [19 §3.2].
- `gptr_tools`: the dispatcher object (9.3).
- `gptr_prompt(session = NULL, preset = NULL, tokens = TRUE)`: frozen system blocks, tool array and first
  message with per-section token estimates.

**SDK verbs** [G1 §4.6]

- `gptr_step(session, n = 1L)`: advance exactly `n` turns.
- `gptr_wait(x, timeout = Inf)`: run sessions or groups to settlement.
- `gptr_on(session, event, handler, matcher = NULL)`: session-scoped hook (Pi event names); returns an
  unsubscribe function.
- `gptr_steer(session, text, as = c("steer", "follow_up", "next_turn"))`: enqueue (the pipe and the pause
  menu call the same function).
- `gptr_cancel(x)`: abort; cancels transfers, kills child trees, records honest partials.
- `gptr_fork(session, at = NULL, envir = c("overlay", "shared"), name = NULL)`: explicit branch into a new
  file with `parentSession`; shares no listeners, queues, connections or processes [10a INFRA-14].
- `gptr_parallel(..., .list = NULL, max_active = NULL, on_error = c("return", "stop"))`: run deferred
  `gptr()` calls concurrently; returns a `gptr_group`.
- `gptr_map(.x, prompt, ..., max_active = 4L, model = NULL, agent = NULL)`: map a prompt over elements.
- `gptr_jobs()`, `gptr_sessions(project = ".", all = FALSE)`, `gptr_resume(id, envir = parent.frame())`:
  background sessions; session files; rebuild a session from its file (gptr or Pi v3).

**Extension API** [G1 §4.5]

- `gptr_api_version()`, `gptr_api_features()`: API version (1.0) and feature strings.
- `gptr_register(spec, .scope = c("session", "user"))`, `gptr_registry(kind = NULL, diagnostics = FALSE,
  tokens = FALSE)`, `gptr_reload()`: top-level registration, listing (with estimated token cost), reload
  with a generation bump.
- `gptr_check(x, error = FALSE)`: conformance for specs, factories, adapters (wire fixtures), plugins.
- `gptr_fake_provider(script, name = "fake")`: scripted provider for offline tests.
- `gptr_tool_result(text = NULL, ..., images = list(), details = NULL, value = NULL, is_error = FALSE,
  terminate = FALSE)`: tool result constructor.
- `gptr_spec(kind, name, ...)`: constructor for plugin kinds and the rarer built-in kinds (`cache_policy`,
  `estimator`, `redactor`, `secret_source`, `env_alias`).

**Spec constructors (22; contracts in section 13)**

```r
gptr_tool(name, description, parameters, execute, annotations = list(),
          exposure = c("r", "direct", "deferred", "hidden"), execution = c("sequential", "concurrent"),
          namespace = NULL, snippet = NULL, guidelines = character(), r_signature = NULL,
          output_schema = NULL, replay = c("never", "safe"), risk = NULL, prepare_arguments = NULL)
gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(),
              type = c("chat", "classifier", "cli"), headers = NULL, discover = NULL)
gptr_adapter(api, transport = c("http_sse", "http_json", "process_jsonl", "inprocess"), build = NULL,
             parse = NULL, stream = NULL, classify = NULL, cache = NULL, capabilities = list())
gptr_router(name, route, description = "")
gptr_model(id, provider, ...)
gptr_mcp_server(name, command = NULL, args = character(), url = NULL, env = NULL, headers = NULL,
                exposure = "r", tool_exposure = list(), timeout = 60, protocol = c("auto", "modern", "legacy"))
gptr_skill(path, name = NULL, description = NULL)
gptr_prompt_template(name, text, description = "", argument_hint = NULL)
gptr_command(name, handler, description = "", complete = NULL)
gptr_hook(event, handler, matcher = NULL)
gptr_policy(name, check, description = "")
gptr_context_block(name, provide, placement = c("turn", "session_start", "event"),
                   authority = c("data", "operator"), budget = 300L)
gptr_compactor(name, should, compact)
gptr_doc_format(name, ext, locate, render, write)
gptr_artifact_type(name, build, check, launch, stop)
gptr_backend(name, start, poll = NULL, cancel, capabilities = list())
gptr_agent(name = NULL, description = "", system = NULL, model = NULL, tools = NULL, skills = NULL,
           backend = c("auto", "inline", "worker", "cli"), max_turns = NULL, returns = NULL, file = NULL)
gptr_ui(name, select, input, questions = NULL, notify = NULL, has_ui = TRUE)
gptr_frontend(name, run)
gptr_setting(name, default, description = "", scope = c("both", "user"), validate = NULL)
gptr_prompt_section(name, text, tier = c("static", "machine"), order = 500, budget = 300L,
                    presets = c("minimal", "default", "coding", "extended"), when = NULL, render_delta = NULL)
gptr_kind(name, validate, resolve = c("first", "all"))
```

---

## 5. Core data structures

Mutable things are environments with an S3 class (session, agent state, reactor, registry, API object,
ctx, inbox, group); immutable values are classed lists (messages, specs, events, usage records, tool
results) or base-typed S3 vectors (System 1). No R6/S7 [G1 §4.3]. In memory, fields are snake_case; the
store boundary maps them to Pi's camelCase JSON with one generated table, so files stay Pi v3
[02 §4.6, 03 §4.2].

### 5.1 The session object (S-8)

`gptr_session` is an environment. Public fields are plain bindings; runtime state sits in `s$.rt`.
Assigning to a field with `$` is refused except for `value` (replay blocks write `res$value = fit` [14 §4.4.6]).

| Field | Meaning |
|---|---|
| `id` | UUIDv7-shaped, RNG-free (short form `s7f3a21`) |
| `text`, `value` | final text of the last settled turn; object designated by `gptr_return()` (not copied) |
| `status` | `idle`, `running`, `waiting_user`, `done`, `error`, `aborted`, `max_turns`, `budget`, `replayed` |
| `model`, `mode`, `turns`, `usage` | current model reference, permission mode, completed turns, `gptr_usage` incl. children |
| `envir`, `file`, `parent`, `depth` | evaluation environment; session file (`NULL` = tempdir/memory); parent id; nesting depth |
| `messages` | active binding: current branch as messages (system excluded) |
| `.rt` | `agent` (L2 state), `store`, `inbox`, `signal`, `listeners`, `frozen` (system blocks, tool declarations, preset), `ctx`, `settings`, `resources`, `doc`, `snapshot`, `memo` (serialisation cache), `children`, `reactor`, `background` |

`print` shows the last answer plus a footer
`<gptr_session s7f3a21 · turn 3 · anthropic/claude-sonnet-5-5 · 12.4k tok · $0.031 · value: <lm>>`;
`format`/`as.character` give the text; `knit_print` emits Markdown; `summary` gives a turn table.

### 5.2 Messages and content blocks

| Block | Fields |
|---|---|
| `text` | `text`, `text_signature`, `kind` (context-block kind), `anchor` (cache anchor) |
| `thinking` | `thinking`, `thinking_signature`, `redacted`, `origin = list(api, provider, model)` |
| `image` | `data` (base64, no newlines), `mime_type` |
| `tool_call` | `id` (provider id verbatim), `name`, `arguments` (named list; `{}` as named empty list), `thought_signature`, `namespace` |

| Role | Fields (besides `timestamp` in ms) |
|---|---|
| `system` | `content`, `sections` (patch semantics), `tools_added`, `tools_removed` (Pi) |
| `user` | `content`, `source` (`prompt`, `steer`, `follow_up`, `extension`, `replay`) |
| `assistant` | `content`, `api`, `provider`, `model`, `response_id`, `response_model`, `usage`, `stop_reason` (Pi's `stop`, `length`, `toolUse`, `error`, `aborted`), `error_message`, `raw_stop_reason`, `thinking_level`, `route` (`api`, `plan-cli`, `system-one`, `emulated`) |
| `tool_result` | `tool_call_id`, `tool_name`, `content` (text/image), `details` (never sent), `is_error`, `usage` (sub-agents), `nested_calls` (Pi limits) |
| `operator` | `kind` (`mode`, `steering_relay`, `section_patch`, `tool_change`, `project_update`), `content`; rendered as mid-conversation system (Anthropic), developer (OpenAI) or user text [G4 §3.5] |
| `r_execution` | `code`, `output`, `exclude_from_context` (`!code`/`!!code`; Pi's `bashExecution`) |
| `custom`, `compaction_summary`, `branch_summary` | Pi's fields; summaries add G4's `checkpoint` state |

Opaque replay data (signatures, encrypted reasoning, `phase`, thought signatures) is resent byte for byte
to the same model and dropped for others by `transform_messages()` [10a INFRA-07/08].

### 5.3 Tool definition and result

A tool is a `gptr_tool()` spec: `parameters` is JSON Schema as nested lists (`I()` keeps arrays),
`execute(input, ctx)` returns a `gptr_tool_result`, a character vector, or throws (converted);
annotations `read_only`, `destructive`, `idempotent`, `open_world`, `requires_user` (MCP names accepted);
`risk(input, ctx)` returns 0-4. `gptr_tool_result`: `content` (the only part the model sees), `details`
(JSON for UI, documents, hooks), `value` (R value for `gptr_tools$<name>()`, memory only), `is_error`,
`terminate`. The `r` tool's `details` is the stable structure other features use [05 §4.5]: `code`,
`record`, `note`, `status` (`ok`/`error`/`timeout`/`interrupt`/`blocked`/`parse_error`), `n_done`,
`n_total`, `created`, `modified`, `removed`, `plots`, `warnings`, `error`, `changes` (wd, option and
env-var names, packages, devices), `elapsed`, `output_path`.

### 5.4 Events

`list(type, session, ts, ...)` of class `gptr_event`, delta-only.
**Provider stream (L1)**: `start`, `text_start|delta|end`, `thinking_start|delta|end`,
`toolcall_start{id, name}|delta|end{tool_call}`, `done{reason}`, `error{reason, error}`, each with a
1-based `content_index` [03 §3.2]. **Agent (L2, Pi names)**: `agent_start`, `agent_end{messages}`,
`turn_start{turn_index}`, `turn_end{message, tool_results}`, `message_start`,
`message_update{kind, content_index, delta}`, `message_end{message}`,
`tool_execution_start|update|end{tool_call_id, tool_name, args, parent_tool_call_id, result, is_error}`
[02 §2.4]. **Session (L3, Pi names)**: `agent_settled`, `queue_update`, `compaction_start|end`,
`auto_retry_start|end`, `entry_appended`, `session_info_changed`, `thinking_level_changed`,
`model_select`. **Extension events (Pi)**: `project_trust`, `resources_discover`, `session_start`,
`session_shutdown`, `session_before_fork`, `session_before_compact`, `session_compact`, `input`,
`before_agent_start`, `context`, `before_provider_request`, `after_provider_response`, `tool_call`,
`tool_result` [05 §3.1]. **gptr additions (10)**: `permission_request`, `route`, `document_write`,
`decision`, `subagent_start|end`, `artifact_start|stop`, `budget_exceeded`, `cache_break`. Pi's dispatch
semantics apply with patches returned instead of mutation; `tool_call`, `document_write`,
`permission_request` fail closed [05 §2.4, G1 §3.2]. The JSON sink writes Pi's names.

### 5.5 Usage and cost

Per request: `input`, `output`, `cache_read`, `cache_write_5m`, `cache_write_1h`, `reasoning`,
`total_tokens`, `cost` (input, output, cache_read, cache_write, total), `tier`, `provider`, `model`,
`route`, `session`, `agent`, `request_id`, `estimated` (CLI and emulated routes), `ts`. Aborted and failed
requests count when usage was reported [10a INFRA-20]. `gptr_usage()` binds records into a `gptr_usage`
data frame with totals; prices come from the catalogue snapshot.

### 5.6 System 1 typed vectors

| Class | Attributes | Notes |
|---|---|---|
| `c("gptr_decision", "logical")` | `prob` (P(TRUE)), `s1` | threshold 0.5 |
| `c("gptr_choice", "character")` | `prob` (n x k, columns in request order), `confidence`, `s1_choices` | classed character, **not** a factor (a factor is truthy in `if()` and warns in `switch()` [04 §2.15]); `s1_output = "factor"` opts in; option names that `if()` reads as logical are rejected [04 verification] |
| `c("gptr_score", "numeric")` | `prob` (n x L), `confidence`, `s1_levels` | expected zero-based level; never an attribute named `levels` |

`s1 = list(model, model_version, question, date, route, emulated, cached, usage)`. Methods `[`, `[[`,
subset-assignment (degrades for foreign values), `c`, `rep`, `format`, `print`, `as.data.frame`, coercions, group
generics that strip attributes; vctrs methods registered lazily [04 §4]. Abstention: none by default;
`na_below = p` -> `NA` below `p`; `stop_below = p` -> `gptr_error_s1_uncertain`.

### 5.7 Artifacts, sub-agents, groups, inbox

- **Artifact** (`artifact.json`) [17 §4]: `id`, `title`, `kind` (`shiny`/`html`), `runner`
  (`callr`/`inprocess`/`fork`), `versions` (`n`, `dir`, `app_sha`, data `{name, class, bytes, path}`,
  `session`), `port` (sticky), `url`, `pid`, `status`, `checks` (`parse`, `launch`, `http`, `session`),
  `screenshot`. Layout under `.gptr/` or `tempdir()`: `artifacts/<id>/app.R` (working copy),
  `artifacts/<id>/vNNN/{app.R, R/gptr_data.R, data/*.rds}`, `artifacts/<id>/run/{run.json, port, log}`.
- **Sub-agent**: a `gptr_session` with `parent`, `depth` and `.rt$backend` (`name`, `handle`: `proc`,
  `fds`, `poll()`, `cancel()` for worker/cli); child events arrive through the reactor and are mirrored
  into the child's transcript, so sub-agents are inspectable, resumable and costed like any session.
- **`gptr_group`** (environment): `members` (named sessions), `label`, `status`; `$name`/`[[i]]` return
  members; `$text` (character vector), `$value` (list), `$usage` (sum) are derived [15 §4.3].
- **Inbox item**: `list(kind = steer|follow_up|next_turn, content, source = pipe|menu|api|file|extension|rpc,
  ts)`; one FIFO per session (Pi's durable-harness unified inbox [02 §2.13]); abort hands queued items back.

### 5.8 Settings

Pi's `settings.json` shape and merge rules [05 §4.9] (objects merge, arrays replace, `defaultTools`
modifiers append, user-only keys dropped from project files, project may only tighten security).
Defaults: `defaultModel` `anthropic/claude-sonnet-5-5` (when Anthropic credentials exist),
`defaultThinkingLevel` `medium`, `system1Model` `typesafe/jev-latest`, `preset` `default`,
`defaultTools`, `toolExposure`, `permissions` (`mode` `manual` with a UI, `allow`/`ask`/`deny`),
`steeringMode`/`followUpMode` `one-at-a-time`, `maxTurns` 50, `compaction` (`enabled`, `softCap` 200000,
`keepRecentTokens` 0, `coldMinTokens` 100000), `retry` (Pi agent-level 3 / 2000 ms / 60000 ms;
`provider.maxRetries` 2, `provider.maxRetryDelayMs` 60000), `httpIdleTimeoutMs` 120000, `cache.tailTtl`
`adaptive`, `document` (`record`, `replay`, `format`, `outputLines` 12, `commitAnswers` false),
`artifacts` (`maxBytes` 1e9, `runner` `callr`), `subagents` (`maxDepth` 1, `maxActive` 8, `maxTasks` 8,
`maxWorkers`), `s1` (`threshold` 0.5, `output` `choice`, `emulate` false, `maxActive` 10), `extensions`,
`skills`, `prompts`, `plugins`, `pluginsAutoload` `attached`, `skillCompat`, `skillsCatalogBudget`,
`contextFiles` true, `defaultProjectTrust` `ask`, `planCli`, `egressAck`, `budgets`, `editFormat` `edit`,
`filters`. Precedence: call > `options(gptr.*)` > environment > trusted project (`.gptr/settings.json`,
`settings.local.json`) > user > defaults.

### 5.9 Session file (Pi v3)

Header `{"type":"session","version":3,"id","timestamp","cwd","parentSession"?,"gptr","r","platform"}`;
entries (`id` 8 hex, `parentId`, ISO `timestamp`) of Pi's types `message`, `model_change`,
`thinking_level_change`, `compaction`, `branch_summary`, `custom`, `custom_message`, `label`,
`session_info` (`context_edit` read, never written). The first message is the frozen `system` message
(sections + tool declarations), so resume reproduces the exact prefix. gptr data lives in `custom` entries
(`gptr.doc_block`, `gptr.replay`, `gptr.decision`, `gptr.mode`, `gptr.artifact`, `gptr.usage`,
`gptr.checkpoint_state`) [14 §3.6]. Lazy creation, exclusive create, appends inside `suspendInterrupts()`
[02 §2.11]. That Pi itself opens gptr files is UNCERTAIN (Pi was never run [02 verification]); gptr reads
Pi files and CI round-trips Pi's documented examples.

---

## 6. Key internal interfaces

### 6.1 Provider adapter contract (L1)

```r
adapter = gptr_adapter(
  api = "anthropic-messages", transport = "http_sse",
  build = function(model, context, options) {
    # context: list(system = list(t0, t1), tools = <frozen declarations>, messages = <projected>)
    # options: signal, reasoning, max_tokens, tool_choice, cache_plan, session_id, headers
    list(url = "https://api.anthropic.com/v1/messages", method = "POST", headers = list(), body = "{...}")
  },
  parse = function(model, options, emit) {
    list(push = function(ev) NULL,      # one decoded SSE event or NDJSON object; emits INFRA-02 events
         finish = function() NULL,      # EOF -> done or error; returns the assistant message
         fail = function(err, aborted = FALSE) NULL,
         message = function() NULL)     # current partial, materialised lazily
  },
  cache = function(parts, caps, session) NULL,   # breakpoint and TTL plan [G4 section 4.3]
  capabilities = list(images = TRUE, mid_system = TRUE, tool_addition = TRUE))
```

`ai_stream(model, context, options, on_event = NULL)` resolves credentials (a vault handle is materialised
only inside the transport and only for the provider's configured origin [G6 §4]), builds the request, adds
it to the current reactor, feeds bytes through `http-sse.R` into `push()` and returns the final assistant
message. **It never throws** for provider or network failures (`stop_reason = "error"`/`"aborted"` with
the partial) [02 §3.3, 10a INFRA-02]. Retries before the first committed delta happen here (C33).
`ai_complete()` is `ai_stream()` without a callback; `ai_classify(model, state, questions, options)` is the
System 1 entry. `process_jsonl` adapters return `list(command, args, stdin, env)` from `build` and expose
`control(msg)` for bidirectional protocols (Claude control requests, Codex server requests).

### 6.2 Transport and reactor (L0)

```r
reactor_new(max_total = 100L, per_host = 100L); reactor_current()
reactor_add_transfer(r, spec, on_data, on_done, on_fail, provider = NULL)    # pipewait = 0
reactor_add_process(r, proc, on_line, on_exit, protocol = c("ndjson", "jsonrpc"))
reactor_add_timer(r, at, fn); reactor_add_pump(r, fn); reactor_add_agent(r, state)
reactor_run(r, until, slice_ms = 100L)          # re-entrant
reactor_cancel(r, ids = NULL)                   # multi_cancel, interrupt(), grace, kill_tree()
```

One iteration: admit queued work under global, per-provider (rate-limit headers) and per-mode semaphores;
if the sequential tool FIFO is non-empty run one tool on the main thread and drain the network with
`multi_run(timeout = 0)`; else `processx::poll()` over `processx::curl_fds(curl::multi_fdset(pool))` and
child pipes for `min(next timer, slice)`, then `multi_run(timeout = 0)`, read pipes, fire timers, run pumps,
advance agents whose transfer completed [15 §4.2, 10a INFRA-01/16]. Timeouts are connect, first byte and
idle on the reactor clock, never total [10a INFRA-05]. A nested `gptr()` inside a tool re-enters
`reactor_run()` on the same pool with its own `until`; its tools run depth-first in the current stack.
`on.exit()` cancels everything the reactor owns.

### 6.3 Agent loop (L2)

```r
agent_new(model, tools, messages = list(), config)       # Pi Agent state
agent_loop(state, prompts); agent_loop_continue(state)   # Pi runAgentLoop / runAgentLoopContinue
agent_step(state)                                        # advance one state; returns its name
# config: stream_fn, convert_to_llm, transform_context, get_api_key, get_steering_messages,
#         get_follow_up_messages, prepare_request, prepare_next_turn, finish_turn,
#         before_tool_call, after_tool_call, tool_execution = "sequential", max_turns = 50L
```

States map one-to-one onto Pi's `runLoop` blocks [02 §2.2]: `start` -> `poll_queues` -> `prepare_turn` ->
`request`/`streaming` -> `tools` (one tool per step; a `length` stop fails all calls unexecuted) ->
`turn_end` (finish_turn) -> `poll_queues` -> `follow_up` -> `done`/`error`/`aborted`/`max_turns`. Steering
is appended only after the complete tool-result message [10a INFRA-12]; hooks must not throw, and if one
does the loop ends with an honest `error` message; an aborted signal is turned into a locally synthesised
aborted message before any request [02 §4.8].

### 6.4 Tool dispatcher

`execute_tool_calls(state, message, calls)` -> `list(messages, terminate)` in source order; per call in
Pi's order and wording [02 §2.3]: `tool_execution_start` -> lookup (`Tool <name> not found`) ->
`prepare_arguments` -> validation (null-dropping, coercion, three-part error; `{"INVALID_JSON": raw}` when
the final strict parse failed) -> `before_tool_call` (6.7; `Tool execution was blocked`) -> abort check
(`Operation aborted`) -> `execute` in `tryCatch` with an interrupt handler -> `after_tool_call` ->
`tool_execution_end` -> tool-result message. Every failure becomes `is_error = TRUE`; an interrupted tool
says "interrupted after 2.3 s; side effects may have occurred" [10a INFRA-04/10]. `run_tool_call()` is the
same pipeline for nested calls (`gptr_tools$...`, ids `<parent>/<n>`).

### 6.5 Evaluator and environment snapshot (L4 services)

```r
r_eval(code, envir, timeout = Inf, plots = c("auto", "capture", "device"), tee = interactive(),
       record = TRUE, guard = TRUE)                                  # -> gptr_eval_result [12 section 3.2]
env_snapshot(envir, prev = NULL, hash_budget = getOption("gptr.hash_budget", 256e6))
env_diff(old, new); workspace_block(snapshot, budget = 600L); changes_block(diff, user_ran, budget = 300L)
```

The evaluator is report 12's [12 §4.3]: `srcfilecopy` parse, static guard, harness options,
`file("", "w+b")` sink with recovery, plot hooks with 768x512 PNG replay, `setTimeLimit(elapsed, transient
= TRUE)` per top-level expression, calling handlers with restarts, symbols printed without
`withVisible()`, value never kept. Default timeout: none at an interactive console, 3,600 s otherwise
(`gptr.r_timeout`). The snapshot fingerprints each binding by address + type + length + attribute and
column addresses + 64 sampled values, with a full `rlang::hash()` up to 50 MB per object inside a 256 MB
per-turn budget [21 §2.9, 12 §3.8], all from leaf functions (PB-E1); promises are never forced, active
bindings never called; the task-callback log adds "user ran: ..." lines [12 §2.C5].

### 6.6 Permission hook (L3 wiring, L4 policies)

```text
session_before_tool_call(call, ctx):
  1. `tool_call` handlers (rank order): list(block, reason) or list(input); error = block
  2. policies: check(call, ctx) -> NULL | list(decision = allow|deny|ask|modify, reason, input);
     combined deny > ask > modify > allow; error = deny
  3. "ask": emit `permission_request` (first decision; error = deny), e.g. a System 1 reviewer
  4. still "ask": ctx$ui$select() when ctx$has_ui, else deny with an actionable reason
```

`builtin:permissions` implements report 18's mode x risk table and rules with G6's secret guard [18 §4.7,
G6 §4]; `builtin:plan` is a second policy. Level-0 `r` code is allowed in every mode, which gives report
20's approval-free inspection without an `r_inspect` tool.

### 6.7 Document writer, session store, MCP client

```r
doc_locate(call = sys.call(), prompt, calls = sys.calls())             # [14 section 4.2]
doc_before_run(session, location, replay_mode)   # "replay" | "run" [14 section 4.4.2]
doc_record(session, location, turn)              # upsert block on agent_end through the backend
store_open(path = NULL, header); store_append(store, entry); store_branch(store, id)
store_context(store); store_fork(store, at, path); store_load(path)     # gptr or Pi v3
mcp_connect(spec); mcp_request(conn, method, params, timeout, progress); mcp_call_tool(conn, name, args)
```

Documents: `doc_format` specs (R, Rmd, qmd, ipynb, transcript) plus `agent_end`/`tool_execution_end` hooks;
writes pass the fail-closed `document_write` event and the redactor, and secret literals become
`Sys.getenv("NAME")` [G6 §4]; Rscript writes are deferred to a finalizer with a sidecar [14 §4.3]. Store:
one kept-open `file(path, "ab")` connection, `flush()` per entry (12 µs [19 §2.2]); each entry serialised
once and memoised for request assembly. MCP: stdio children and HTTP streams both run on the reactor, so an
MCP call from inside `r`, a CLI child and a model stream can be in flight together; both eras, MRTR,
progress-reset deadlines, `notifications/cancelled`, ASCII JSON, OAuth that never opens a browser
implicitly [16 §4.5].

### 6.8 Sub-agent backends

```r
gptr_backend("worker",
  start = function(spec, ctx) NULL,     # spec: session skeleton, prompt, objects, export, limits -> handle
  poll = function(handle) list(),       # JSONL events since the last poll (reactor-driven)
  cancel = function(handle) NULL,       # interrupt, 5 s grace, kill_tree (checks is_alive first)
  capabilities = list(parallel = TRUE, live_objects = FALSE, ask = "forward"))
```

`auto` -> `cli` for CLI-only models, the agent file's backend when given, else `inline` (single and
parallel) [15 §4.3]. Inline: overlay `new.env(parent = envir)`, per-agent L'Ecuyer RNG stream swapped
around each tool, explicit export (conflict `error` for parallel runs), no binding-lock guard (PB-E1).
Worker: `callr::r_bg()` with `supervise`, `cleanup_tree`, `user_profile = FALSE`, `libpath = .libPaths()`;
JSONL events on stdout, answers on stdin [15 §3.6].

### 6.9 CLI providers and background service

`cli-claude` runs one long-lived `claude -p --input-format stream-json --output-format stream-json
--verbose --include-partial-messages --tools "" --strict-mcp-config --setting-sources ""
--disable-slash-commands --mcp-config <file> --permission-prompt-tool stdio --system-prompt-file <file>
--model <full id>` per session (never `--bare`), prompt on stdin; `stream_event` lines feed the Anthropic
normaliser; gptr's tools are an in-process `sdk` MCP server over the control protocol; `can_use_tool` goes
to the permission hook; interrupt is a control request [07 §4]. `cli-codex` runs `codex app-server`
(JSON-RPC; gptr tools as dynamic tools calling back into the dispatcher; `turn/steer`, `turn/interrupt`,
`thread/resume`) when the installed version passes a schema probe, else `codex exec --json
--ignore-user-config -` with the in-session HTTP MCP server [08 §4, 16 §4.6].

Background sessions schedule `later::later(tick, 0.05)` chains that run the reactor with a zero slice while
the console is idle; they evaluate in an overlay and deny permission asks unless the mode is `auto`. httpuv
servers are serviced by the reactor pump `later::run_now(0)`, never `httpuv::service(0)` [16 §2.11].

### 6.10 Context assembly (L3)

`session_freeze(session)` renders system blocks T0/T1 and the tool array once;
`session_request_context(session, target)` returns `list(system, tools, messages, view, cache_plan)`
following G4's placement table [G4 §4.2]: first user message = `<project_instructions>` (AGENTS.md/CLAUDE.md
root to cwd, then `.gptr/vignette.Rmd`; cache anchor) + `<environment>` + `<mode>` + `<workspace>` +
`<attached>` + prompt; later state as appended blocks or operator entries; per-(entry, api, same-model)
memoised serialisation; body by concatenation; prefix guard against the previous request to the same model
(`cache_break` names the culprit). Before each request: extension `context` handlers (guarded) ->
projection -> hand-off transform -> adapter render.

---

## 7. Positions

### 7.1 Open decisions D-01 .. D-28

| ID | Position | Rationale and evidence |
|---|---|---|
| D-01 | Settled by S-10. The own layer sits on **curl** (multi) and **processx** only; no httr2. | Only curl multi survived resumed interrupts in every phase and streamed at true latency [02 §5.5, 15 §4.1, 09 §2]; httr2 blocks the event loop during the header wait [10a V-8]; one transport path removes the httr2 minimum-version question. |
| D-02 | S3 on environments (mutable), classed lists/vectors (immutable); no R6/S7 anywhere. | 1.6-1.9 µs vs 3.8-4.5 µs per call, 3-5 µs vs 47-76 µs per object [G1 §2.3]; no R6/S7 on hot paths [10a §16]. Pi's classes become environments plus functions (P1). |
| D-03 | Direct tools **read, r, edit, write** (Pi's four, `bash` -> `r`); grep/find/ls exposed as R functions and direct in `preset = "coding"`; `ask` direct only with a UI; `agent`, `artifact`, `apply_patch`, `tool_search` opt-in; no shell, no `r_inspect`, no todo. | Pi's default [01 §2]; Claude Code moved search into its shell tool [20 §2]; 33/26/18 vs 235/180/98 tokens [PB-E2]; level-0 `r` code is approval-free in every mode, covering `r_inspect` [18 §4.7]; todo is off by default in Claude Code and Codex [20 §4]. |
| D-04 | `envir = parent.frame()` + magrittr fix + `envir =`; inline sub-agents, forks and background sessions use `new.env(parent = envir)` with explicit export; plan mode a throwaway child. **No binding-lock guard.** | [12 §2.B4, 15 §4.5, 18 §4.7]; PB-E1: `lockBinding()` makes the value immutable, so a guarded 5 GB object would be copied per tool call. An overlay write costs one extra copy on the parent's next in-place edit (documented). |
| D-05 | `gptr()` returns the **session environment** (S-8). Idle + pipe = follow-up turn now; running + pipe = steering message, returns at once. Explicit branch `gptr_fork(s, at, envir = "overlay")` (new file with `parentSession`; in documents it is the user's line `f = gptr_fork(s)` and later blocks carry the fork's `session=`). Data-first pipes are told apart by the class of the first dot; magrittr works but labels context `.`. System 1 returns vectors. Background sessions ship as experimental. | [12 §2.E, 10a INFRA-14, G1 §4.6]; one inbox serves every producer (C16). |
| D-06 | `gptr(q, x, model = jev, choices = , levels = )` -> `gptr_decision` / `gptr_choice` (**classed character**) / `gptr_score`; no abstention by default; `na_below`/`stop_below`; emulation only with `s1_emulate = TRUE`; requests on the reactor with bounded rounds. | "Factor-like" overturned [04 §2.15]; INFRA-18 names kept [10a §14]; silent emulation would spend System 2 tokens (S-12). |
| D-07 | `rlang::enquo/enquos` capture; known name wins over a same-named variable (like `library()`), `!!` escape, one-time shadowing message; bound unknown symbols give their character value; unbound ones are literal names. | Base `substitute()` resolved forwarded dots wrongly and `...elt()` left sticky references [12 §2.D2]; tidyllm/vitals export `claude`, `codex`, `claude_code`, so "a bound variable wins" (04, 05, 09) would break aliases whenever they are attached [10 Q4]. |
| D-08 | Report 14's block grammar, agent chunks/cells, modes `auto/replay/live/record`, "gptr() never executes a recorded block", deferred Rscript writes; System 1 in control flow never written, top-level System 1 gets a one-line summary block. | [14 §3-4]; resolves C19. |
| D-09 | Pi v3 JSONL tree in `.gptr/sessions/` (exact resume) + the runnable document (human). | [02 §4.6, 10a INFRA-13, 14 §3.6]. |
| D-10 | `.gptr/` only via `gptr_init()` (explicit path = consent; missing path = interactive confirm else error) or the interactive recording prompt; otherwise sessions and artifacts in `tempdir()`, S1 cache in memory, no document writes. User files under `R_user_dir("gptr", ...)` (or `GPTR_HOME`, or an existing `~/.gptr`). | [13 §2, 05 §4.2, 17 §4]; NS-9's argument-free `gptr_init()` works interactively. |
| D-11 | `plan`, `manual`, `edits`, `auto`; default `manual` with a UI; risk 0-4; rules deny > ask > allow > mode; level 4 asks even in `auto`; project may only tighten; without a UI an ask is a denial with an actionable reason, and the `ask` tool in `manual`/`plan` stops the run with `gptr_error_needs_user` (NS-12); classifier advisory. | [18 §4.7, 13 §4, G6 §4]. |
| D-12 | `inline` (default), `worker` (callr), `cli`; `fork` opt-in on Unix terminals; `auto` as in 6.8. | [15 §4.4, 06 §4]. |
| D-13 | gptr-owned reactor (curl multi, `pipewait = 0`, `host_con = 100`) + `processx::poll()` + timers + pumps; no promises/coro; `later` only as pump and background scheduler. | [15 §4.1-4.2, 10a INFRA-01/16]. |
| D-14 | Own MCP client (both eras) and server; stdio and HTTP on the reactor with gptr's SSE parser; other harnesses' user-level configs imported automatically, project-level after trust; default exposure `r`; server transports: Claude `sdk`, Codex dynamic tools, httpuv fallback. | [16 §4, 07 §4, 08 §4]. |
| D-15 | Unmodified `claude`/`codex` CLIs via processx; ChatGPT plan natively via Sign in with ChatGPT; no Claude OAuth or impersonation; CLI providers opt-in with a notice. | [03 §2.13, 07 §2, 08 §4]. |
| D-16 | Agent Skills; `function(gptr)` factories; plugins as R packages or directories with `inst/gptr/{plugin.json, skills, prompts, agents, mcp.json, extensions}`; `.claude-plugin` consumed unmodified; lazy activation. | [05 §4.10, 16 §4.9, G1 §4.4]. |
| D-17 | Shiny app in a callr child with a snapshot, validated up to a chromote session check; registry under `.gptr/artifacts/` or `tempdir()`; in-process `shiny::startApp()` (shiny >= 1.14) opt-in for objects too large to snapshot. The model writes `app.R` with `write` and launches with `gptr_tools$artifact()` guided by a skill; a direct `artifact` tool is opt-in. | [17 §4 + verification]; 41 vs 688 tokens per request [PB-E2]. |
| D-18 | `provider/model[:thinking]`, dynamic aliases, snapshot in `inst/extdata`, refresh on request only, quoted canonical ids in history. | [09 §4.2-4.9]. |
| D-19 | Provider usage for sent context + calibrated estimator for the rest (chars/4 prose and code, chars/2 tool output); G4 threshold and cold rule; truncation at entry with spill files; no micro-compaction. | [21 §2.8, G4 §4.4-4.5, 12 §3.5]. |
| D-20 | Nine Imports (section 8). | Each justified in section 8. |
| D-21 | No compiled code in v1; report 21's Rcpp procedure and watch list kept on file. | [21 §1]. |
| D-22 | Vault + handles, one redactor at every sink, own `.env` parser with aliases, origin-bound credentials, child-environment allowlists. | [G6 §4, 10a INFRA-22]. |
| D-23 | `Depends: R (>= 4.2.0)`. | UTF-8 on recent Windows, pipe placeholder [13 §2]. |
| D-24 | Fake provider, base-R mock SSE server, wire fixtures, fake CLIs, pure-R MCP server, adapter conformance, copy-safety, prefix-stability, secrets end-to-end and layer tests; `dev/bench` token benchmark. | [10a INFRA-24, G4 §4.9, G6 §4]. |
| D-25 | Pi's event names and dispatch semantics canonical, 10 gptr events added, Claude/Codex names only through the import alias map. | [05 §3.1, G1 §3.2]; the lens. |
| D-26 | cli rendering, chunk-invariant streaming markdown, `!`/`!!`, Pi's slash commands + `/mode`, `/env`, `/cost`, `/undo`, `/save`; Ctrl-C pause menu; interrupt returns to the prompt in the REPL, re-signals in programmatic calls. | [18 §4]. |
| D-27 | No chunk engine by default; `options(gptr.knitr_engine = TRUE)` registers one (glue's pattern) that is replay-only during `R CMD check` and vignette builds; `gptr()` in R chunks with `knit_print` is the supported path. | [14 §4.6, 13 §4]; keeps S-2. |
| D-28 | `gptr()` + 77 `gptr_*` exports; `agent()` exists only in the `agents =` mask. | [G1 §4.7, 10 Q4]. |

### 7.2 Cross-track conflicts (critic's list; known conflicts 1-18 are items C1-C18)

| # | Conflict | Resolution |
|---|---|---|
| C1 | R6 vs S3 + env | D-02 (R6 arrives through callr but is never called). |
| C2 | Transport and SSE parsing | D-13; no httr2 anywhere; gptr's vectorised byte splitter flushes a final unterminated event and is ~17x faster than `resp_stream_sse()` [21 §2.6, 08 verification]; System 1 fan-out on the reactor with bounded rounds, so httr2's unbounded 429/503 retry cannot occur [04 §2]. |
| C3 | Imports budget | Nine Imports (section 8); later/httpuv in Suggests, checked at run time by background sessions, `gptr_mcp_serve()` and the OAuth loopback (paste/stdio fallbacks); yaml in Imports (a hand parser lost 4 of 37 real skills [05 §4.14]). |
| C4 | NSE capture and ambiguity | D-07. |
| C5 | Evaluator and plot size | Hand-rolled evaluator [12 §2.A2]; `r` plots 768x512 at res 96 (~532 tokens); `gptr_config(plot_size = "large")` gives 1000x700 at res 120 (~900 tokens) [17]; artifact screenshots keep report 17's size. |
| C6 | Tool surface, name, todo, edit result | D-03; name `r` (D-03, 12, 14, G4); `apply_patch` shipped but opt-in (`editFormat = "apply_patch"`/`"auto"`, the latter for sessions starting on a GPT-5.x Responses model) until the benchmark shows it helps [20 §5.7]; no todo; edit results are Pi's one-line message, plus the diff only when the fuzzy fallback changed the matched text; the full diff always in `details` [01 §4, 11 §4]. |
| C7 | Dispatcher naming | One object `gptr_tools` (not `tools` [06]); MCP under `gptr_tools$mcp$<server>$<tool>()`; report 11's data functions are `gptr_tools$read/grep/find/ls()`; G4's prompt text updated accordingly (342 tokens [PB-E2]). |
| C8 | Sub-agent default and limits | `auto` -> inline for single and parallel runs, cli for CLI-only models, worker explicit; one `auto` default across `gptr_agent()`, the `agent` schema and `gptr_map()` (fixes 15's inconsistency); depth 1, 8 tasks and 4 concurrent per call, 8 inline globally, workers min(4, cores - 1); name "worker"; mori not used (saves transfer time only [15 §2.7]). |
| C9 | System 1 API shape | D-06; only through `gptr(..., model = jev)`. |
| C10 | Return value | D-05; report 12's result fields become session fields. |
| C11 | Claude plan bridge | `cli-claude` with the control protocol and the in-process `sdk` MCP server (6.9); the httpuv fallback writes a per-server `timeout` above 60 s into `--mcp-config` [07 verification]; provider id `cli-claude`, alias `claude_code` kept for the north star, name-use and "claude.ai login" questions flagged for the maintainer before release [07 §2, 03 verification]; opt-in, notice, and a warning when `ANTHROPIC_API_KEY` or another billing-switch variable would move billing to the API. |
| C12 | ChatGPT plan route | `gpt` models with `auth = "chatgpt"` use Sign in with ChatGPT natively (gptr's loop, in-memory tools); `model = codex` uses `cli-codex` (app-server with stdio dynamic tools when the version passes a schema probe, else `exec --json` + in-session HTTP MCP); Codex's 19-38K tokens per turn are shown in `gptr_providers()` [08 §4-5]. |
| C13 | MCP eras | Both: stdio probes `server/discover` (5 s) then falls back to `initialize`; HTTP inspects the 4xx body; era cached per server for 7 days [16 §4.5]. |
| C14 | Session format vs compaction | Pi v3 tree, strictly append-only; failed attempts projected out; compaction is an appended in-conversation checkpoint; no micro-compaction (+32 % cost and 25 invalid thinking blocks in G4's simulation [G4 §2.10]). |
| C15 | Workspace consent | D-10; north-star §8's `.gptr/artifacts/...` holds after `gptr_init()`, otherwise the same tree under `tempdir()`. |
| C16 | Steering channels | One inbox (5.7) fed by the pipe, the pause menu, `gptr_steer()`, extensions, the file inbox `.gptr/sessions/<id>.inbox.jsonl` and later RPC; drained at Pi's poll points; steering placed after the complete tool-result message as an operator relay [10a INFRA-12, G4 §3.5]. |
| C17 | Script history under Rscript/`source()` | Report 14 unchanged; reading `source()` frame locals is wrapped in `tryCatch` with srcref and content-match fallbacks and can be switched off (`gptr.doc_source_frames = FALSE`) should CRAN object (UNCERTAIN [14 verification]). |
| C18 | Copy safety | Leaf discipline; no binding-lock guard, no `mget()` undo snapshots (PB-E1); `/undo` restores conversation and files, object snapshots opt-in (`gptr.undo_objects`, size-capped, one copy documented); full hash <= 50 MB per object within 256 MB per turn, sampled fingerprints beyond (ALTREP may show as "modified", harmless); artifact snapshots capped at 1e9 bytes with the in-process runner as the escape. |
| C19 | System 1 in the document | Control-flow calls are the user's code and are never written; answers go to the S1 cache (input hashed) and, inside a session, a `gptr.decision` entry; top-level statements get one summary line `#> 20 decisions (jev-1.13.0, 2026-09-29): 14 TRUE, mean p 0.91`. REQ-26(c) holds because the calls are document content. |
| C20 | Project instructions | G4: AGENTS.md (else CLAUDE.md) per directory root to cwd, then `.gptr/vignette.Rmd` last (additive, deduplicated) in the first user message's anchored block; system prompt frozen and stating the precedence [G4 §4.2]. A listed deviation from Pi. |
| C21 | Hook taxonomy | D-25; INFRA-11's `before/after_tool_call` are L2 loop hooks implemented from `tool_call`/`tool_result` handlers and policies (6.6). |
| C22 | Permission modes, plan mode | D-11; plan = report 18's scratch-env semantics + report 20's `<proposed_plan>` saved to `.gptr/plans/` and offered as "Execute (edits/auto/manual) / Keep planning" [18 §4.7, 20 §4.8, G4 §3.4]. |
| C23 | Compaction thresholds, estimator | G4's formula and cold rule; calibrated estimator (D-19); Pi's `compaction.*` keys kept, `reserveTokens` derived. |
| C24 | Skill catalog and activation | Budget max(8000 chars, 1 % of window) [16 §4.8]; over budget, descriptions are cut to 250 characters [05 §4.7], then dropped least-recently-used first, names kept; activation through `read` (Pi; no skill tool whose enum would change the tool array), `/skill:name`, `skills =`. |
| C25 | Agent files | `Bash`/`PowerShell` -> `r` (S-4; 15, 16); directories, later wins: `~/.pi/agent/agents`, `~/.claude/agents`, `R_user_dir/agents`, then trusted project `.pi/agents`, `.claude/agents`, `.codex/agents` (TOML), `.gptr/agents`; plugin agents at plugin rank. |
| C26 | Shell tool vs S-4 | No shell tool, not even opt-in; the compact helpers of gap G5 are `gptr_tools$run/sh/py/sql/engine()` (9.3), classified level 3, secret-free environments [G6 §4]. |
| C27 | Exported names | D-28; `mcp_*`, `artifact()`, `decide()` become `gptr_mcp*`, `gptr_artifact*`, `gptr(model = jev)`. |
| C28 | knitr engine | D-27. |
| C29 | File-tool recipes | grep: report 21 (readBin, `grepRaw(fixed = TRUE)` and whole-file `(?m)` PCRE prefilters, NUL sniff, early exit; never `readLines()` per file). read: in-memory raw newline index up to 16 MiB [11], chunked `grepRaw` scan + sparse index cached by (path, size, mtime) beyond [21]. diff: patience + Myers capped at D = 256, no diffobj [21 §2.3]. find: Pi's semantics (`**/` prepended to patterns with `/`) [11 verification]. |
| C30 | Event-loop integration | The reactor owns the loop; later/httpuv are reactor pumps (`later::run_now(0)` per iteration while a server or background job exists), never `httpuv::service(0)`; artifact children run their own watchdog; background ticks poll with a zero timeout where later cannot watch processx pipes (Windows, LIKELY [15 verification]). |
| C31 | Committed S2 cache | `.gptr/cache/s2/` git-ignored by default (`commitAnswers = false`); `.gptr/cache/s1/` committed (hashes and answers only); all cache writes redacted. Replay needs only the document, so privacy costs nothing but the answer text. |
| C32 | Default models | Pinned full ids from the catalogue: Anthropic `claude-sonnet-5-5` (north-star banner, effort medium, half Opus's price), Google `gemini-3.8-flash` [09], OpenAI the catalogue default; `opus`, `sonnet`, `haiku`, `flash`, `gpt`, `jev` dynamic aliases. |
| C33 | Retry constants | Provider level: up to 2 retries before any committed delta; delay `retry-after-ms` > `retry-after` > `min(0.5 * 2^i, 8)` s x (1 - 0.25 u), `u` from the clock (RNG-free); server delays above 60 s fail fast; never the spend-cap 429 [02 §2.8, 10a INFRA-06, 07 §2]. Agent level: Pi's 3 retries at 2 s x 2^(n-1), cap 60 s. System 1: 3 bounded rounds. |

---

## 8. Dependencies

`Depends: R (>= 4.2.0)`; `NeedsCompilation: no`; `SystemRequirements:` optional `claude` and `codex`
CLIs. Base packages: grDevices, graphics, stats, tools, utils.

| Import | Why it is required | Minimum |
|---|---|---|
| curl | the reactor: multi handles, `multi_fdset`, `multi_cancel`, per-handle timeouts, `pipewait = 0` [15 §4.1] | 6.4.0 |
| processx | child processes, `poll()` over curl fds and pipes, `curl_fds()`, `kill_tree()` [15 §4.2] | 3.8.0 |
| callr | worker sub-agents and artifact apps (`r_bg`, library paths, result files) [15 §4.4, 17 §4] | 3.7.0 |
| ps | RAM and PID checks, orphan sweeps (already a processx dependency) [19 §2, 15 §4.7] | 1.7.0 |
| jsonlite | all JSON | 1.8.8 |
| rlang | `enquo/enquos`, `obj_address`, `hash` [12 §2.D2] | 1.1.0 |
| cli | console rendering and capabilities, vectorised `hash_sha256` [18 §4.10, 14 §4.9] | 3.6.0 |
| openssl | cryptographic random bytes (tokens, PKCE) without the RNG, sha256, base64 without line breaks [03 §4.6] | 2.0.0 |
| yaml | SKILL.md, agent and prompt frontmatter [05 §4.14] | 2.3.0 |

Nine Imports is under report 13's budget of about 12 [13 §3]. Dropping httr2 costs ~200 lines (request
building, PKCE, redacted headers) and buys one transport, no minimum-version tracking and no blocking path.
Suggests (behind `requireNamespace()` with a fallback or a classed `gptr_error_missing_package`): httpuv,
later, shiny, bslib, chromote, ragg, knitr, rmarkdown, rstudioapi, reticulate, DBI, vctrs, stringi,
magick, keyring, filelock, jose, codetools, testthat (>= 3.2.0), withr. Data-work packages (data.table,
arrow, duckdb, ...) are detected and recommended, never declared [19 §2].

---

## 9. The model-facing surface

### 9.1 Presets (tool array + sections, frozen per session; tokens from PB-E2)

| Preset | Direct tools | Extra sections | Tools + T0 | Used for |
|---|---|---|---|---|
| `minimal` | read, r, edit, write | Pi-style core only | 686 + 602 = **1,288** | sub-agents, cheap models |
| `default` | read, r, edit, write (+ ask with a UI) | r_session, r_performance (short), documents, system1 (if configured) | 686 + 1,418 = **2,104** (+336 with ask) | everything else |
| `coding` | default + grep, find, ls | same | 1,199 + 1,437 = **2,636** | file-heavy work, package development |
| `extended` | coding + ask + artifact | full r_performance, artifacts, delegation | ~4,400 | models with a 4,096-token cache minimum (Haiku 4.5, Gemini 3.x) [G4 §4.3.4] |

T1 (frozen per machine/project) adds the skills catalog, the R-signature catalog of MCP and plugin tools,
`<r_env>` and `APPEND_SYSTEM.md`: 1,013 tokens in G4's fixture (4 skills, 2 servers, 9 signatures).

### 9.2 Tools

| Tool | Default | Parameters (sketch) | Permission class (risk) | Tokens |
|---|---|---|---|---|
| `read` | direct | `{path, offset?, limit?}` (Pi, byte-identical) | 0 in project, 1 outside, 2 protected/secret paths | 155 |
| `r` | direct | `{code, record? = true, note?, timeout?}` | classifier level 0-4 (+ secret guard); level 0 allowed in every mode | 202 |
| `edit` | direct | `{path, edits: [{oldText, newText}], replaceAll?}` (Pi + `replaceAll`); a pasted `*** Begin Patch` is applied | 2 in project (auto in `edits`), 3 outside/protected | 241 |
| `write` | direct | `{path, content}` (Pi) | as edit | 87 |
| `grep` | R function (direct in `coding`) | `{pattern, path?, glob?, ignoreCase?, literal?, context?, limit? = 100, output?: content/files/count, sort?}` | 0 | 235 / 33 |
| `find` | R function (direct in `coding`) | `{pattern, path?, limit? = 1000, sort?: path/mtime/size, reverse?, type?}` (Pi's `**/` rule) | 0 | 180 / 26 |
| `ls` | R function (direct in `coding`) | `{path?, limit?, long?, sort?: name/mtime/size}` | 0 | 98 / 18 |
| `ask` | direct with a UI | `{questions: [{id, header?, question, type: single/multi/text, options? (<= 9), allow_other?, default?}] (1-4)}` [18 §3.6] | read-only; no UI: defaults (edits/auto) or stop (manual/plan) | 336 |
| `agent` | opt-in | `{agent?, task?, tasks? (<= 8), chain?, model?, backend?: auto/inline/worker/cli, objects?, export?}` [15 §3.5] | inherits children's calls; children may only tighten | ~300 |
| `artifact` | opt-in | `{id?, title?, app?, edits?, data?, kind?: shiny/html, screenshot?}` [17 §4] | 3 (runs model code in a process) | 352 |
| `apply_patch` | `editFormat` | V4A freeform on Responses, `{patch}` elsewhere [20 §5] | as edit | ~200 |
| `tool_search` | when deferred tools exist and the provider has no native search | `{query, n?}` | 0 | ~90 |
| `mcp__<server>__<tool>` | exposure `direct` only | server `inputSchema` (strict off) | annotations trusted only for trusted servers, else 3 | 150-330 |

Results follow Pi: text and images to the model, `details` to hooks, UI and documents; 2,000 lines /
50,000 characters with a spill file (head 40 % + tail 60 % for `r`, head for the others) [01 §4, 12 §3.5].

### 9.3 Tools as R functions (`gptr_tools`)

What is not a direct tool is reachable inside one `r` evaluation, which is how gptr composes many
operations per round trip (S-12). Calls go through `run_tool_call()` (same validation, hooks and gate as
model calls, nested ids); an enclosing `r` call approved at level L pre-approves nested calls up to L.

```r
gptr_tools$read(path, offset = NULL, limit = NULL)
gptr_tools$grep(pattern, path = ".", glob = NULL, ignore_case = FALSE, literal = FALSE,
                context = 0L, limit = 100L, output = c("content", "files", "count"), sort = "path")
gptr_tools$find(pattern, path = ".", limit = 1000L, sort = c("path", "mtime", "size"), type = "f")
gptr_tools$ls(path = ".", sort = c("name", "mtime", "size"), long = FALSE)
gptr_tools$write(path, content); gptr_tools$edit(path, edits)
gptr_tools$run(command, args = character(), stdin = NULL, timeout = 60, wd = NULL, pass = character())
gptr_tools$sh(script, shell = NULL, timeout = 60, pass = character())
gptr_tools$py(code, timeout = 60); gptr_tools$sql(con, query, n = 1000L); gptr_tools$engine(name, code, ...)
gptr_tools$artifact(id, app = NULL, data = character(), kind = "shiny", screenshot = TRUE)
gptr_tools$search(query, n = 5L); gptr_tools$describe(name)
gptr_tools$mcp$github$search_code(q = "useR 2026")
```

Polyglot glue (closes gap G5 without a shell tool, S-4): `run()` is `processx::run()` with an argument
vector, a timeout and a child environment without registered secrets unless listed in `pass` [G6 §4]; its
print shows status, the first and last 20 lines and byte counts. `sh()` writes the script to a temp file and
runs the detected shell (`bash`, `zsh` or `sh`; on Windows Git Bash if present, else
`powershell -NoProfile -File`), named once in `<r_env>`. `py()` uses reticulate when installed, else
`python3` through `run()`. `sql()` wraps `DBI::dbGetQuery()` with a row cap. `engine()` runs any registered
knitr language engine. All are classifier level 3 (processes). `artifact()` takes `app` as a path or as code; `NULL` means the working copy `<root>/artifacts/<id>/app.R` that the model wrote with `write`.

### 9.4 System prompt outline (Pi's named sections, frozen at session start)

| Tier | Section | When | Budget / measured |
|---|---|---|---|
| T0 | preamble (untagged) | always | 120 / 78 |
| T0 | `<tools>` snippets + Pi's "other custom tools" line | always | 250 / 83 |
| T0 | `<rules>` Pi's edit guidelines byte-identical, "use = and \|>", "name the objects you created", artifact pointer | always | 450 / 292 |
| T0 | `<r_session>` live-session rules, one-call composition, `gptr_tools`, glue helpers, sub-agents as `gptr()`, `gptr_return()`, forbidden calls | `r` active | 450 / 342 |
| T0 | `<r_performance>` short (full in `extended`) [19 §3.1] | `r` active | 150 / 127 |
| T0 | `<documents>` `record`, `note`, editing earlier blocks | a document is bound | 250 / 186 |
| T0 | `<system1>` | System 1 configured | 150 / 123 |
| T0 | `<delegation>` | `extended` or `+agent` | 150 / 125 |
| T0 | `<modes>`, `<context>` (block meanings, instruction precedence) | always | 120 / 84, 130 / 103 |
| T1 | `<addendum>` (APPEND_SYSTEM.md) | file present | 1,000 |
| T1 | `<skills>` compact catalog | skills visible, `read` active | max(8000 chars, 1 %) / 283 for 4 |
| T1 | `<r_tools>` R signatures of MCP and plugin tools, overflow line `gptr_tools$search()` | such tools exist | 3,000 / 331 for 9 |
| T1 | `<r_env>` R, cores, RAM, shell, fast packages, broken packages [19 §3.2] | `r` active | 450 / 399 |

`.gptr/SYSTEM.md` (trusted) or `gptr(system = )` replaces preamble, tools and rules (Pi's custom prompt);
sections are added, replaced or removed through `gptr_prompt_section()`. Mode blocks (42-116 tokens) and
context blocks are user-role data, never system text [G4 §3.4-3.5].

---

## 10. Walkthroughs

**Runs** = functions in order; **Disk** = files written; **Model sees** = request content (o200k proxies).

### NS-1 Interactive session on a large in-memory object

1. `library(gptr)`: `.onLoad` registers lazy S3 methods only.
2. `gptr()`: rule 1 -> console frontend -> `session_new(envir = globalenv())` -> resource loading
   (built-ins through `ext_load()`, user settings, `.gptr/` found = consent, trust, skills, MCP configs read
   but not connected, AGENTS.md and vignette.Rmd read as text) -> `session_freeze()` (read, r, edit, write,
   ask) -> first-use egress confirmation -> transcript target asked once -> banner with the workspace line
   from `env_snapshot()` (`pbmc <Seurat 3,012,448 cells x 33,538 features, 5.1 GB>`; leaf describers).
3. Prompt typed -> `input` event -> first user message -> `session_run()` -> `reactor_run()` with the pause
   menu -> `agent_step()` -> `ai_stream()` (BP1 on T0, BP2 on the project block, both 1 h; tail 1 h because
   interactive) -> deltas rendered by `md_stream()`. **Model sees** tools 1,022 + T0 1,435 + T1 ~1,013 +
   first message (project ~218, environment 68, mode 50, workspace ~60, prompt ~20) ≈ 3,900 tokens.
4. `r` call `pbmc = FindNeighbors(pbmc, dims = 1:30)`: `tool_call` handlers -> `builtin:permissions`
   (modifies existing `pbmc`, larger than `gptr.protect_size` -> level 3) -> `manual` asks
   `r pbmc = FindNeighbors(...) allow? [y]es / [a]lways / [n]o` -> `r_eval()` in `globalenv()` with live
   output and no timeout -> 107-token result -> `message_end` persisted -> code buffered for the block.
   Ctrl-C here opens the pause menu; "continue" resumes the computation where it stopped [02 §4.7].
5. FindClusters and FindAllMarkers the same way; final answer; `agent_end` -> block written into the
   transcript; `agent_settled` -> footer with tokens and cost.
6. `!dim(markers)` -> passthrough in `envir`, output shown, an `r_execution` message queued (Pi's
   `bashExecution`), a `# direct R` section in the transcript. `/mode auto` -> a `<mode name="auto">` block
   leads the next user message (no prompt rebuild). `/exit` -> `session_shutdown`; `pbmc` and `markers`
   are in `globalenv()`.

**Disk**: `.gptr/sessions/<ts>_<id>.jsonl` (system, user, assistant, toolResult, `r_execution`,
`gptr.doc_block`, `gptr.mode`) and the transcript `.R` file.

### NS-3 The pipe steers one session object

1. The innermost `gptr("Load ... normalise")` runs first: rule 8 -> `doc_locate()` -> no block -> run ->
   session `s`.
2. `s |> gptr("Now run a PCA ...")` (rule 3): `s` is idle -> follow-up turn, led by `<workspace_changes>`
   when objects changed -> same `s` returned.
3. `... |> gptr("Plot PC1 ...", model = opus)`: `model_change` entry, `model_select` event,
   `transform_messages()` renders the history for Opus (foreign thinking to text, signatures dropped, tool
   ids normalised) [03 §2.9]; Opus's cache starts cold. One session file, three blocks with `call=1..3`
   [14 §3.1]; re-sourcing replays all three at zero tokens.
4. `qc = gptr("Run QC on pbmc ...", pbmc)`: `<attached name="pbmc">` (<= 300 tokens). The user's
   `table(pbmc$percent.mt > 20)` is logged; `qc |> gptr("Use 15% ...")` starts with `user ran: ...`;
   `qc$value` is what the agent passed to `gptr_return()`.
5. `gptr_fork(qc) |> gptr("Try a 10% cut-off as well")`: `session_before_fork` -> new file with
   `parentSession` -> overlay environment, so the branch cannot overwrite the main line's objects.

### NS-4 System One decisions inside control flow

1. `if (gptr("Is this abstract about a randomised controlled trial?", abstract, model = jev))`: `jev` is a
   known alias -> rule 5 -> `s1_call()`: state `{"abstract": "..."}`, question `noul` (wire name) with
   default criteria, client-side validation [04a] -> cache lookup -> `ai_classify()` on the reactor
   (~250-450 input tokens, $0.042 per million) -> `gptr_decision` with `prob` -> `decision` event -> `if()`
   reads a length-1 logical. Nothing is written (inside `if`).
2. `is_rct = gptr(..., abstracts, model = jev)`: 20 states, at most 10 in flight, bounded rounds (~400 ms
   for 20 [04a]); top-level statement -> one summary line in the document; `table(is_rct)` and
   `attr(is_rct, "prob")` work; `dplyr::if_else()` needs `as.logical()` (documented).
3. `choices = c("liver", "lung", "brain", "other")` -> `gptr_choice`, probability columns in request order
   although the wire order differs [04a].
4. `while (gptr("Is the residual plot acceptable?", diagnostics(fit), model = jev))`: the context call is
   re-evaluated each iteration; new inputs miss the cache; the loop is steered at System 1 cost.

### NS-6 Sub-agents in parallel and across providers

1. `agents = list(stats = agent(model = opus, skills = statistics), code = agent(model = codex), biology =
   agent(model = gemini, skills = single_cell))` is evaluated in the alias mask (`agent = gptr_agent`) ->
   rule 6 -> `auto`: stats and biology inline, code `cli-codex`.
2. One reactor carries two HTTP streams and one Codex app-server child; inline agents run `r` in overlays of
   `globalenv()` (zero-copy reads), one R tool at a time; Codex's dynamic-tool calls come back over stdio
   into the same dispatcher and gate; skills are preloaded as `<skill_content>`; children use `minimal`
   (1,288 static tokens).
3. Result: a `gptr_group`; `reviews$stats` is a session; `gptr_usage(reviews)` sums all three (Codex
   route `plan-cli`, estimated); each child has a session file with `parentSession`.
4. `gptr("Summarise this cohort", cohorts, parallel = 4)` -> rule 7 -> one inline session per element,
   four at a time -> `summaries$text` is a character vector.

### NS-7 The script is the history

1. After each top-level `gptr()` statement a block is written: `# >>> gptr:7f3a21
   model=anthropic/claude-sonnet-5-5 date=2026-09-29 prompt=<12hex> sha=<8hex> tokens=... session=...`,
   the successful `record = TRUE` code verbatim, `#>` outputs (12 lines), `## Decision:` lines from
   `note`, `# <<< gptr:7f3a21` [14 §3.1].
2. `source("analysis.R")` again: each call finds its fresh block, returns a replayed session at zero
   tokens, and the block's code runs as ordinary R.
3. `options(gptr.replay = "live")`: under `source()` the old block is already parsed, so gptr replays with a
   warning pointing to `gptr_source()`; `gptr_source(replay = "live")`, knitr and line-by-line IDE runs
   regenerate the block in place (atomic write, md5 check, IDE cursor moved past it) [14 §4.4].
4. The agent rewrites an earlier block with `edit` on the document path; the backend refreshes `date` and
   `sha`. Rmd/qmd get `gptr-<id>` chunks; notebooks get cells with `metadata.gptr` (not while open in
   Jupyter).

### NS-8 Artifacts are Shiny apps

1. `gptr("Build me an explorer ...", markers)`: `markers` attached.
2. The model reads the `shiny-artifacts` skill (~1.5 k tokens, once), writes
   `.gptr/artifacts/marker-explorer/app.R` with `write` (~700 output tokens of bslib code), then runs
   `gptr_tools$artifact("marker-explorer", data = "markers")` in `r`.
3. `builtin:artifacts` copies the working `app.R` to `v001/`, snapshots `markers` with
   `saveRDS(compress = FALSE)` (cap 1e9 bytes), writes `R/gptr_data.R`, runs static checks, starts a
   `callr::r_bg()` child (supervise, cleanup_tree, parent-PID watchdog) that publishes its port by atomic
   rename, polls HTTP 200, runs the chromote check (RNG saved and restored), takes a screenshot, emits
   `artifact_start`.
4. **Model sees** `ok, marker-explorer v001, http://127.0.0.1:4827, checks: parse/launch/http/session ok`
   plus the screenshot (~1,080 tokens) and fixes problems before answering. **Console**:
   `artifact  marker-explorer  ->  http://127.0.0.1:4827   (running in background)`. **Disk**:
   `.gptr/artifacts/marker-explorer/{artifact.json, app.R, v001/, run/}`; the document gets
   `#> [app] .gptr/artifacts/marker-explorer/app.R` and a replayable `gptr_artifact_open("marker-explorer")`.

### NS-11 A whole workflow that reads like R

1. `prep = gptr(..., pbmc) |> gptr(...) |> gptr(...)`: as NS-3, three blocks after the statement.
2. The analyst's `pbmc = FindNeighbors(...) |> FindClusters(...)` runs as plain R and is logged for the next
   turn.
3. The `for` loop: `cell_type = gptr(..., top, model = jev, choices = ...)` per cluster (cached per input,
   nothing written inside the loop); `cell_type == "unclear"` compares a classed character.
4. Inside `if`: `gptr("Cluster {cl} has ambiguous markers ({top}). ...", pbmc) |> gptr(...)`: light
   interpolation fills `{cl}` and `{top}` from the loop variables; a new session per ambiguous cluster;
   calls nested in control flow get no blocks, so re-sourcing runs them live (the session files keep the
   record; call-site replay is deferred, section 12).
5. `gptr("Build a Shiny app ...", pbmc)`: as NS-8, but `pbmc` is 5 GB; the skill and the size cap steer the
   model to ship cluster sizes, markers and UMAP coordinates; with `gptr_config(artifact_runner =
   "inprocess")` (shiny >= 1.14) the app reads `pbmc` live while the console is idle.
6. Re-sourcing: the pipeline blocks replay, System 1 answers come from the cache, only the ambiguous-cluster
   investigations call a model.

---

## 11. Delivery

### 11.1 Milestones (each ends in a runnable, tested state)

| Milestone | Plans | Exit test (offline unless stated) |
|---|---|---|
| M0 Kernel | P01-P04 | `--as-cran` green; factories load transactionally and roll back; secrets grep finds 0 keys; reactor meets INFRA-01 on the mock (first delta < 0.35 s, six streams within 10 % of the slowest), INFRA-05, INFRA-06 |
| M1 Streaming AI | P05-P06 | every adapter replays golden fixtures; conformance suite passes (built-ins, fake); hand-off fixtures validate (INFRA-07/08); chunk invariance incl. split UTF-8 (INFRA-23) |
| M2 Agent runtime | P07-P09 | report 02's 24 loop, 42 store and 26 recovery checks ported and passing; JSONL survives SIGKILL; one compaction + one retry on overflow; 20-turn prefix test; `gptr_prompt()` within section 9 budgets |
| M3 Live R | P10-P12 | 19-case evaluator torture suite; copy-safety suite incl. PB-E1; file-tool oracles (git ls-files, ripgrep, `git apply`) [11]; 11-row permission matrix [18 §4.7]; NS-2 with the fake provider |
| M4 Gateway and documents | P13-P14 | NS-1 via scripted REPL (`.stdin = TRUE`), NS-3, NS-7; deferred Rscript writes; knitr record/replay |
| M5 System 1 | P15 | NS-4, NS-5 on a mocked `/systemone`; opt-in live test with the maintainer's key via `gptr_env()` |
| M6 Ecosystem | P16-P17 | NS-10; MCP both eras on the pure-R server; a toy plugin package passes `gptr_check()` |
| M7 Agents and plans | P18-P19 | NS-6, NS-9 with fake CLIs; INFRA-16 mixed run; INFRA-19 abort leaves no process tree |
| M8 Artifacts and release | P20 | NS-8, NS-11; token benchmark baseline; `--as-cran` on Linux, macOS, Windows, R-devel |

### 11.2 Implementation plans

| Id | Title | Scope | R files | Depends on |
|---|---|---|---|---|
| P01 | Foundations | skeleton, DESCRIPTION, `.lintr`, CI (Windows, `LC_ALL=C`), utils, JSON encoding, test setup, layer test | `utils-*.R`, `json-encode.R`, `zzz.R` | - |
| P02 | Extension kernel | registry, kinds, constructors, API object, ctx, dispatch semantics, transactional/lazy loading, versioning, `gptr_check()` basics | `ext-*.R` | P01 |
| P03 | Secrets and credentials | vault, redactor, `.env`, credential store, origin binding, child environments, `gptr_env()`, `gptr_redact()` | `auth-secrets/redact/dotenv/store/resolve/childenv/builtin.R` | P01, P02 |
| P04 | Transport kernel | reactor, requests, SSE/NDJSON, retry, rate limits, processes, mock server | `http-*.R` | P01 |
| P05 | AI core | message model, events, partial JSON, validation, `ai_stream()`, transform, overflow, thinking, cost, fake provider, conformance | `provider-types/events/adapter/stream/transform/overflow/thinking/cost/fake.R`, `json-partial.R`, `json-schema.R` | P02-P04 |
| P06 | Native adapters, catalogue | Anthropic, OpenAI Responses, OpenAI-compatible + compat, Gemini; catalogue; OAuth, SIWC; `gptr_models/login/logout/providers()` | `provider-anthropic/openai-*/google/builtin.R`, `catalog-*.R`, `auth-oauth.R`, `auth-siwc.R` | P05 |
| P07 | Agent loop | runLoop state machine, tool pipeline, queues, signal/interrupt policy, `max_turns` | `agent-*.R`, `tool-spec.R` | P05 |
| P08 | Session runtime and store | session object, run with recovery, Pi v3 store, inbox, settings, resources, trust, workspace, usage/budgets, fork/resume, SDK verbs | `session-object/runtime/store/convert/inbox/settings/resources/trust/workspace/usage/fork.R` | P02, P03, P07 |
| P09 | Context, caching, compaction | sections, presets, instruction files, blocks, request assembly, cache plans, prefix guard, checkpoint compaction, calibrated estimator, `gptr_prompt()`, `dev/bench` harness | `prompt-sections/builtin/blocks/instructions.R`, `session-context/cache/compact.R` | P06, P08 |
| P10 | Evaluator, introspection, `r` | evaluator, plots, guard, snapshot/diff, describers, task log, capabilities, `gptr_tools`, glue helpers, copy-safety suite | `eval-*.R`, `env-*.R`, `tool-functions.R`, `tool-glue.R` | P02, P07 |
| P11 | File tools | walker, gitignore, globs, read, write, edit, diff, grep, find, ls, apply_patch | `tool-fs/read/write/edit/diff/patch/grep/find/ls/builtin.R` | P07, P10 |
| P12 | Permissions, plan, ask, UI | classifier, rules, gate, plan mode, `ask`, `gptr_ui` backends, `gptr_permissions/risk()` | `perm-*.R`, `tool-ask.R`, `console-ui.R` | P08, P10, P11 |
| P13 | Gateway and console | `gptr()`, NSE, interpolation, values, REPL, reader, renderer, commands, pause menu, JSON sink, `knit_print`, background | `gptr-*.R`, `console-repl/reader/render/commands/menu/jsonl/knitr/builtin.R`, `session-background.R` | P08, P09, P12 |
| P14 | Script-as-history | locate, blocks, atomic document I/O, Rmd/qmd, ipynb, IDE, replay, transcripts, `gptr_doc/source/cache()` | `doc-*.R` | P13 |
| P15 | System One | adapter, typed vectors, vctrs, vectorised front, cache, emulation, summary blocks | `s1-*.R` | P05, P13, P14 |
| P16 | Skills, templates, plugins | skills, templates, plugin packages/directories, Claude plugin compatibility, shipped skills | `skill-*.R`, `prompt-templates.R` (plugin half of `ext-load.R` with P02) | P02, P09 |
| P17 | MCP | config/imports, TOML, client (eras, stdio/HTTP on the reactor), OAuth, exposure, server, `gptr_mcp*()` | `mcp-*.R` | P04, P10, P16 |
| P18 | Sub-agents | inline and worker backends, agent files, `agent` tool, groups, `gptr_parallel/map/agents/jobs()` | `subagent-*.R` | P10, P13 |
| P19 | Subscription CLIs | `cli-claude`, `cli-codex`, fake CLIs, consent | `cli-*.R` | P17, P18 |
| P20 | Artifacts and release | artifact store, runners, ladder, skill, `gptr_artifact*()`, north-star e2e, precomputed vignettes, benchmark baseline, CRAN hardening | `artifact-*.R` | P10, P13, P14, P16 |

---

## 12. Risks, mitigations, deferrals

| Risk | Mitigation |
|---|---|
| Vendor policy moves against the CLI plan bridge (Agent SDK "claude.ai login" wording, "Claude Code" name rule) [07 §2] | Opt-in, notice, no credentials handled, removable by filter; maintainer asks Anthropic before release; ChatGPT has an official native route |
| Preview interfaces drift (SIWC field rules, Codex app-server schema) [08] | Schema probes against the installed binary, `exec --json` fallback, API-key routes |
| MCP revisions break the wire (2026-07-28) [16 §2.1] | Thin protocol layer, both eras, fixtures per era |
| Nothing verified on Windows | Windows CI from M0; `.exe` resolution, shim refusal, rename fallbacks; features documented LIKELY until verified |
| Pause menu and `readline()` in RStudio, Positron, Jupyter unverified [02 §7, 18 §7] | Manual test matrix; abort-only fallback |
| In-process evaluation cannot be sandboxed | Default `manual`, critical guard in `auto`, secret guard, classifier documented as advisory |
| Copy safety depends on R internals [12 §7] | Fresh-process tracemem suite on R-release and R-devel; PB-E1 cases pinned |
| Long R computations outlive 5-minute caches [G4 §2.9] | Adaptive 1 h tail TTL |
| Pure-R search slower than ripgrep on huge trees [11, 21] | Limits, pruned walker, watch list |
| Pi-readability of gptr session files unverified [02 verification] | A goal, not a promise; Pi's documented examples round-tripped in CI |
| Prompt injection via context files, skills, MCP, sub-agent reports | User-role placement, trust gating for code and config, fail-closed permissions, secrets never in context |
| CRAN reviewer concerns (caller-frame evaluation, document writes, data egress) [13 §7] | User-initiated actions only, `gptr_init()` consent, tempdir defaults, egress acknowledgement, `context = "none"` |
| Surface size (78 exports, ~130 files, 22+ kinds) | Layer test, conformance suite, experimental labels for `artifact_type`, `frontend`, custom kinds [G1] |
| Light interpolation or background sessions surprise users | Literal-only bare symbols with an off switch; background runs in an overlay, denies asks unless `auto`, labelled experimental |
| Claude/Gemini tokenizers are not public [21 §2.8] | Estimator calibrated from provider usage |

**Deferred beyond v1**: RPC mode; Bedrock Converse/SigV4, Vertex, Azure AD (their OpenAI-compatible
routes work); Gemini Interactions; Copilot; call-site replay of `gptr()` calls inside control flow;
writing open notebooks; OpenTelemetry; the knitr engine by default; shinylive export beyond copying;
`fork` beyond opt-in; mori/mirai transports; Pi's durable format 4; TUI renderers; a `/tree` UI and branch
summaries (the store supports branches); provider-native compaction plugins; a System 1 reviewer for
`auto` (the `permission_request` event is ready); todo tools; `apply_patch` as the GPT default; Claude
plugin hooks beyond the alias-mapped subset; MCP sampling and legacy SSE resumption.

---

## 13. Extensibility map (S-11)

Every row registers through `gptr$register(spec)` in a `function(gptr)` factory, `gptr_register()` at top
level, or a call argument; ranks: call 0 > trusted project 1 > user 3 > plugin 5 > built-in 6; kinds with
`resolve = "all"` keep every record [G1 §3.6]. Built-ins take exactly this path.

| Category | Registration and contract | Built-ins on it | Shipped by an R package as | Used by a third-party layer for |
|---|---|---|---|---|
| HTTP providers | `gptr_provider()`: data; `auth` resolver per request | Anthropic, OpenAI, Google, OpenRouter, Groq, Ollama, ... | factory or `plugin.json` models | a corporate endpoint by data alone |
| Wire adapters | `gptr_adapter()`: never throws; INFRA-02 events | anthropic-messages, openai-responses, openai-completions, google, typesafe-system-one, cli-claude, cli-codex, fake | factory + `gptr_check()` fixtures | a Bedrock adapter |
| CLI providers | `gptr_provider(type = "cli")` + `process_jsonl` adapter with `control()` | `builtin:cli` | factory | another agent CLI |
| System 1 providers | `gptr_provider(type = "classifier")` + `classify()` | Jev, emulation | factory | a local logprob classifier |
| Routers | `gptr_router(name, route(request, ctx))`, 50 ms, System 1 via `ctx$decide()` | optional `builtin:jev-router` (Pi's example) | factory | `model = cheap_first` |
| Models | `gptr_model()` | catalogue snapshot | `plugin.json` | house models with prices |
| Tools | `gptr_tool(..., exposure, execution, risk)` | `builtin:tools`, `builtin:r` | factory; `<r_tools>` line (~36 tokens) until promoted | `gptr_tools$<name>()` or direct |
| MCP servers | `gptr_mcp_server()` (`mcpServers` shape + exposure) | `builtin:mcp` (replaceable) | `inst/gptr/mcp.json` | domain servers in a bundle (NS-10) |
| Skills | `gptr_skill(path)` (Agent Skills) | `inst/gptr/skills` | `inst/gptr/skills/` or `inst/skills/` | progressive disclosure of know-how |
| Prompt templates | `gptr_prompt_template()` (Pi grammar) | `inst/gptr/prompts` | `inst/gptr/prompts/*.md` | `/review`-style commands |
| Slash commands | `gptr_command(name, handler(args, ctx))` | console commands | factory | console verbs |
| Hooks / events | `gptr_hook()`, `gptr$on()`, `gptr_on(session)`; Pi semantics, patches | store, document writer, renderer, usage roll-up | factory (lazy on first provided event) | audit logs, UI bridges |
| Permission policies | `gptr_policy(name, check)`; deny > ask > modify > allow; error = deny | `builtin:permissions`, `builtin:plan` | factory (project filters cannot disable them) | organisation rules, a System 1 reviewer |
| Context describers | `gptr_context_block()`; S3 `gptr_describe()` | environment, workspace, changes, attached; describers for common classes | `S3method(gptr::gptr_describe, cls)` with gptr in Suggests | Bioconductor objects in 300 tokens |
| Prompt sections | `gptr_prompt_section()`; stable across turns | `builtin:prompt` | factory | a `<bioconductor>` section |
| Compaction | `gptr_compactor(name, should, compact)` | checkpoint compactor (replaceable) | factory | provider-native compaction |
| Cache policies, estimators | `gptr_spec("cache_policy" / "estimator", ...)` | per-API plans, calibrated estimator | factory | gateway-specific caching |
| Document formats | `gptr_doc_format()` + fail-closed `document_write` | R, Rmd, qmd, ipynb, transcript | factory | Org-mode or targets writers |
| Artifact types | `gptr_artifact_type(name, build, check, launch, stop)` | shiny, html | factory | Quarto dashboards, plumber APIs |
| Sub-agent backends | `gptr_backend()`; never block the reactor > 50 ms; cancel kills the tree | inline, worker, cli, fork (opt-in) | factory | mirai or Slurm backends |
| Agent definitions | `gptr_agent()` or `.md` files | reviewer, planner | `inst/gptr/agents/` | domain agents |
| UIs, front ends | `gptr_ui()`, `gptr_frontend(name, run)` | console, none, scripted, rstudio; REPL, jsonl, knit | factory | a Shiny chat front end |
| Settings | `gptr_setting()` | core settings | factory | plugin configuration |
| Secrets | `gptr_spec("secret_source" / "redactor" / "env_alias", ...)` [G6 §4] | `builtin:secrets` | factory | PHI redaction rules |
| New categories | `gptr_kind()` + `gptr_spec()` | - | factory | a workflow engine's "stage" kind |

**Pi extension-API parity.** On the `gptr` API object: `on`, `register_tool`, `register_command`,
`register_provider`, `register_mcp_server`, `register_router` (Pi's `registerVirtualModel`),
`register_setting` (Pi's `registerFlag`), all sugar for `register(spec)`; `events$emit/on`. On `ctx` (and,
as in Pi, on `gptr` delegating to the dispatching session and erroring while extensions load):
`send_message`, `send_user_message(deliver_as =)`, `append_entry`, `session_name`, `set_label`, `exec`
(processx, no shell), `active_tools`/`set_active_tools` (changes appended, the tool array never rebuilt),
`all_tools`, `commands`, `settings`, `set_model`, `thinking`/`set_thinking`; gptr additions `envir`,
`mode()`, `ui`, `has_ui`, `decide()`, `usage()`, `state()`, `secret()`, `redact()`, `execute_tool()`.
Not ported: shortcuts, renderers, widgets, themes.

**A third-party agentic layer** needs only exported verbs:

```r
panel_review = function(task, models = c("opus", "gemini", "codex"), judge = "opus") {
  sessions = lapply(models, function(m) gptr(task, model = m, preset = "minimal", .run = FALSE))
  names(sessions) = models
  done = function() all(vapply(sessions, function(s) s$status %in% c("done", "error"), logical(1)))
  while (!done()) for (s in sessions) gptr_step(s)       # the reactor interleaves their I/O
  gptr("Merge the reviews into one list of issues", model = judge,
       reviews = vapply(sessions, function(s) s$text, ""))
}
```

**API versioning** [G1 §4.5]: `gptr_api_version()` starts at 1.0 and moves only with the extension API;
MINOR = additive (handlers ignore unknown payload fields, validators accept unknown spec fields); MAJOR =
breaking, with CRAN's two-week notice to reverse dependencies (`which = "most"`). Plugins declare
`"gptr": {"api": ">= 1.0, < 2"}` or `Config/gptr/api`, negotiate with `gptr$has()`, and see deprecations
once per session (`gptr_deprecated`; `options(gptr.deprecations = "error")` in plugin CI) for at least one
MINOR release and six months. A failing plugin is disabled with a diagnostic; start-up never fails.

---

## 14. Token-efficiency analysis (S-12)

### 14.1 Static prefix per preset (PB-E2, o200k proxy)

| Preset | Tools | T0 | T1 (fixture) | Total |
|---|---|---|---|---|
| minimal (sub-agents) | 686 | 602 | 0 | **1,288** |
| default | 686 | 1,418 | 1,013 | **3,117** |
| default + ask (console) | 1,022 | 1,435 | 1,013 | **3,470** |
| coding | 1,199 | 1,437 | 1,013 | **3,649** |
| default without MCP, skills, System 1 | 686 | 1,295 | 399 | **2,380** |

For comparison: G4's seven-tool default 3,619 on the same fixture; Pi ~1.3 k [G4 §4.8]; Claude Code 3-18 k
[07]; Codex 19-38 k per turn [08]; btw's 31 tools ~11.6 k [10]. After the first request the prefix is read
from cache at 0.05-0.1x (1 h anchors at the end of T0 and of the project block), also across sessions of
the same project within the hour [G4 §4.3].

### 14.2 Environment description and tool results

`<environment>` 68 tokens; `<workspace>` 122 for six objects including a 5 GB Seurat object (budget 600);
`<workspace_changes>` ~71 when something changed, 0 otherwise; `<attached>` <= 300 per object; `<r_env>`
399, once [G4 §2.8]. A FindNeighbors + FindClusters log is 107 tokens (chars/4: 90; chars/2: 180; the
calibrated estimator converges on the provider count) [PB-E2]; a plot ~532; an artifact screenshot ~1,080;
worst case one result = the 2,000-line / 50,000-character cap, tightened to 8,000 characters past half the
compaction threshold [G4 §4.4.5].

### 14.3 One north-star task end to end (NS-1 on claude-sonnet-5-5)

Prices $2 in / $10 out per million, cache read 0.1x, 1 h write 2x [07]. Three `r` calls and an answer:

| Request | Input | Cache read | Written | Output |
|---|---|---|---|---|
| 1 | ~3,890 | 0 | ~3,890 | ~120 |
| 2 | ~4,150 | ~3,890 | ~260 | ~100 |
| 3 | ~4,400 | ~4,150 | ~250 | ~120 |
| 4 | ~4,800 | ~4,400 | ~400 | ~250 |
| **Total** | **~17,240** | **~12,440 (72 %)** | **~4,800** | **~590** |

Cost ≈ 4,800 x $4/M + 12,440 x $0.2/M + 590 x $10/M ≈ **$0.028**. A second session in the same project
within the hour reads T0, T1 and the project block from cache, so its first request drops from ~$0.016 to
~$0.002. The 5 GB object never enters the context and is never reloaded.

### 14.4 What each choice saves

| Choice | Effect | Evidence |
|---|---|---|
| Four direct tools; grep/find/ls as R functions | -513 per request; 33/26/18 vs 235/180/98 per tool | PB-E2 |
| Artifacts = `write` + `gptr_tools$artifact()` + skill | 41 vs 688 per request; skill body paid only when used | PB-E2 |
| Shiny instead of HTML/JS | 3.1-3.7x fewer tokens per app; data by name instead of 127 k inline | [17 §2] |
| MCP and plugin tools as R signatures | ~36 vs ~328 per tool; 9 tools in 331 tokens (full schemas 24x) | [G1 §2.5, G4 §4.8] |
| Composition in one `r` call | 109 vs 1,532 tokens in G1's example; ~15 tokens per sub-agent call | [G1 §4.8] |
| Compact skill catalog, read-tool activation, budget | 283 vs 409 (XML) for 4 skills; no skill tool | [G4 §2.8, 16 §4.8] |
| Frozen prompt, append-only transcript | a per-turn rebuild costs 2.7x ($0.876 vs $0.323) | [G4 §2.9] |
| Checkpoint instead of micro-compaction | avoids +32 %; checkpoint request 9.4x cheaper than a fresh summary | [G4 §2.9-2.10] |
| Adaptive 1 h tail TTL | keeps hits across > 5-minute R computations | [G4 §2.9] |
| System 1 for judgements | ~250-450 Jev tokens at $0.042/M per decision vs a System 2 turn per item | [04a] |
| 768x512 plots | 532 vs ~900 tokens per plot | [12 §3.5, 17] |
| Diffs only when non-empty; budgeted describers | 0 on idle turns; <= 300 per object | [G4 §4.2] |
| Minimal preset for sub-agents | 1,288 vs 3,117 per child | PB-E2 |
| Edit diff only after fuzzy matching | Pi's one-line result on the common path | [01 §4] |
| Redaction markers | 6-10 vs 26-104 tokens per key | [G6 §4] |

### 14.5 Accounting, budgets, benchmark

- **Accounting**: usage records per request (5.5); `gptr_usage()`; `gptr_prompt()` per-section sizes;
  `gptr_registry(tokens = TRUE)` shows what each plugin costs.
- **Estimation**: provider usage for sent context; chars/4 (prose, code), chars/2 (tool output), 1 per CJK
  character, image formulas for the rest; the difference between consecutive requests' reported input and
  the estimate of the entries added in between updates a per-(provider, kind) calibration factor
  [21 §2.8, G4 §4.5].
- **Budgets**: `budget = list(tokens, cost, turns, seconds)` per call and per-session defaults;
  `budget_exceeded` and status `budget` (resumable).
- **Cache health**: the prefix guard counts `cache_break` events in `$usage` and names the plugin or hook
  responsible; `options(gptr.check_prefix = "error")` in development.
- **Benchmark** (`dev/bench/north-star/`, not shipped): one scenario per north-star example with a scripted
  fake model and the real harness (prompt, blocks, tool results, documents), so counts are reproducible.
  Metrics: static prefix, first-request and total input, cached share, output, tool-result sizes and cost,
  counted with rtiktoken (dev only) and with gptr's estimator. A committed baseline fails CI on > 5 % growth
  of first-request or total tokens [G4 §4.9]; an opt-in live mode records provider usage to refresh the
  calibration.

# gptr — Design Decision Register

Every architecture proposal must take an explicit position on each decision
below. "Preliminary position" is the lead designer's starting point; it may be
overturned by research evidence (`dev/research/`), but only with a stated
reason. "Settled" decisions come from the maintainer and are not open.

Requirements referenced as `REQ-nn` are in `00-vision-brief.md`.

## Settled by the maintainer

| ID | Decision |
|----|----------|
| S-1 | **`gptr(...)` is the single gateway.** No prompt → interactive console session. Prompt → the function that receives it and runs the agent. One variadic function, not a family of entry points. |
| S-2 | **Prompts are always quoted strings.** Bare names are for identifiers only (models, skills, extensions, plugins, session objects). |
| S-3 | **R only, with a narrow Rcpp exception** for benchmark-proven hot paths, each with a pure-R reference implementation (REQ-01). |
| S-4 | **No bash tool.** The execution tool evaluates R in the live session; shell access goes through R. |
| S-5 | **Artifacts are Shiny apps**, HTML inside Shiny is the fallback. |
| S-6 | **The project-instructions file is `.gptr/vignette.Rmd`.** |
| S-7 | Old API is gone; no deprecation shims. |
| S-9 | **House code style: `=` for assignment (never `<-`) and the native pipe `|>` (never `%>%`)** in package code, tests, docs, examples, generated history documents and plans. Enforced by `.lintr` with `assignment_linter(operator = "=")`; styler only with `force_assignment_op` removed. See `dev/plan/00-conventions.md` section 4. |
| S-11 | **Everything can be a plugin** (REQ-41). One public, documented, versioned extension API covers every capability category (providers, routers, tools, MCP servers, skills, prompts, commands, hooks, permission policies, context describers, compaction, document writers, artifact types, sub-agent backends, agent definitions, front ends). Built-ins are implemented on that API. R packages ship plugins, and third parties can build agentic layers on gptr's public API. |
| S-12 | **Token efficiency is a first-class, measured design criterion** (REQ-42): R/Shiny semantic compression, in-memory compute referenced by name, composition of many operations in one R evaluation, R as polyglot glue (shell, Python, SQL, knitr engines) through compact helpers, lean and cache-friendly context, System 1 for cheap decisions, calibrated token accounting, budgets and a token-efficiency benchmark suite. Every design choice with a token cost states it. |
| S-10 | **Own LLM infrastructure, superseding the R LLM ecosystem** (REQ-40). gptr implements its own transport, streaming, provider adapters, message/tool-call model, sessions and concurrency, designed for agents. No R LLM package (ellmer, tidyllm, chattr, gptstudio, mall, btw, mcptools, corteza, aisdk, ...) is a dependency (neither Imports nor Suggests), and v1 ships no bridge to them. Their designs may inspire gptr, with attribution where code ideas are ported. This settles D-01. |
| S-8 | **`|>` is the steering operator on one session object** (REQ-18). `gptr()` returns an object that *is* (or directly carries) the agent session; piping it into `gptr("...")` appends a steering message or follow-up prompt to that same session. Continuing never silently forks; forking is an explicit call. The `.R` file must read like ordinary R: prompts, R code, control flow and Jev typed outputs interleaved, with `|>` chains recording how the agent was steered. |

## Verified facts that constrain the design

Executed on R 4.4.3 (`dev/research/assets/lead/gateway.R`):

- A length-1 logical carrying a class and attributes works directly in `if()`,
  `while()`, `&&`, `isTRUE()`. So a System One yes/no can return
  `structure(TRUE, class = c("gptr_decision", "logical"), prob = 0.93)` and be
  used as a condition with no unwrapping.
- `if (NA)` is an error ("missing value where TRUE/FALSE needed"). A
  low-confidence decision therefore must not silently become `NA` inside a
  condition; abstention needs an explicit policy (see D-06).
- Subsetting a classed vector with `[` **drops** class and attributes unless a
  `[` method is defined. Vectorised decisions need `[`, `[[`, `c`, `rev`,
  `format`, `print` methods that carry the probabilities along.
- One variadic `gptr(...)` can distinguish all call shapes by inspecting the
  dots: no arguments → interactive; unnamed plain character → prompt; a
  `gptr_result`/`gptr_session` → continuation (this is what makes
  `gptr("a") |> gptr("b")` work); any other unnamed object → attached context,
  labelled with its deparsed expression (`mtcars |> gptr("describe")` yields
  the label `mtcars`).
- Bare identifiers resolve via `match.call()` without rlang:
  `model = jev`, `skills = c(seurat, plotting)`, while `model = "opus"` still
  works.
- `parent.frame()` of a top-level `gptr()` call is `globalenv()`; inside a
  function it is that function's frame. Evaluating in `parent.frame()` gives
  the in-memory behaviour without the package ever naming `.GlobalEnv`.

From Pi source (read first-hand, commit `1b347794`):

- Pi's default model-visible tools are `read`, `bash`, `edit`, `write`.
  `grep`, `find`, `ls`, `powershell` exist but are opt-in; a read-only preset
  is `read`, `grep`, `find`, `ls`.
- Pi's system prompt is assembled from named, independently replaceable
  sections (`preamble`, `tools`, `rules`, `docs`, `addendum`,
  `project_context`, `skills`, `cwd`, custom), each wrapped in an XML tag of
  the same name. Tools contribute one-line snippets and guideline bullets.
- System One wire protocol: `POST {baseUrl}/systemone`, header
  `Authorization: Bearer <key>`, body
  `{ model, state, questions: { <id>: { type, instructions, criteria } } }`
  with question types `choice`, `score`, and boolean (public name `bool`, wire
  name `noul`). Response `{ answers, usage: {input_tokens, output_tokens} }`
  where a choice answer has `choice`, `probabilities`, `confidence`; a score
  answer has `score`, `confidence`; a boolean answer has `noul` = probability.
  Key environment variable: `TYPESAFE_API_KEY`. Model id seen: `jev-latest`.
- Pi uses Jev as a **router**: a virtual model classifies task complexity, then
  plans on a strong model and hands implementation to a cheap one after the
  first successful edit.

## Open decisions

### D-01 Provider layer: own implementation or ellmer — SETTLED by S-10
gptr builds its own agent-grade LLM infrastructure. No ellmer bridge, not even
in Suggests. The remaining open question is only *which low-level HTTP
packages* the own layer sits on (curl, httr2, or both); see D-13 and the
transport conflict.

### D-02 Object system
Preliminary: S3 classes. Mutable things (session, agent, registry) are
environments with an S3 class; immutable things (messages, results, decisions)
are lists/vectors with an S3 class. No R6/S7 dependency unless a proposal shows
a concrete benefit.

### D-03 Model-visible tool surface
Preliminary default set: `r` (evaluate R in the live session), `read`, `write`,
`edit`, `grep`, `find`, `ls`. On request: `ask` (ask the user), `agent`
(sub-agent), `artifact` (Shiny), `shell` (via `system2`/`processx`, off by
default). Everything else (help lookup, object description, MCP tools) is
reachable as ordinary R functions from the `r` tool rather than as separate
model-visible tools. Proposals must justify every tool beyond the first four.

### D-04 Evaluation environment
Preliminary: `envir = parent.frame()` captured at the `gptr()` call, explicit
`envir =` argument to override. Inline sub-agents get
`new.env(parent = caller)` so reads fall through without copying and writes
stay local.

### D-05 Return value and pipe semantics (constrained by S-8)
Preliminary: `gptr("...")` returns the **session object itself** — an
environment-backed S3 object (reference semantics), so every variable bound to
it sees the same, growing session. Printing it shows the latest answer;
`$text`, `$value` (the R object the agent designated as its result), `$usage`,
`$history` expose the rest. Piping it into `gptr("...")` appends a turn to the
same session and returns the same object, so

```r
s = gptr("load and clean the counts")
s |> gptr("use TPM, not CPM")         # steers s itself
s$value                               # reflects the steered state
```

Open sub-questions each proposal must answer:
- Steering a **running** session: for a background/worker session
  (`gptr(..., background = TRUE)`), piping a prompt into it while it is still
  working should enqueue a Pi-style *steering* message (delivered at the next
  turn boundary); piping into an idle session is a *follow-up* turn. Is this
  unified behaviour feasible and worth it in v1?
- Explicit fork: name and semantics (e.g. `gptr_fork(s)`), and how a fork is
  recorded in the script-as-history document.
- How a data-first pipe (`df |> gptr("...")`) is told apart from a session pipe
  (dispatch on the class of the first argument).
- The canonical operator is the native pipe `|>` (maintainer, 2026-09-29).
  Because gptr dispatches on its first argument, magrittr's `%>%` works the
  same way at no cost; docs and examples use `|>` only.
- How System 1 calls (`model = jev`) fit: they return typed vectors, not a
  session, so they are used inside conditions rather than in steering chains.
Interactive `gptr()` returns the session invisibly on exit, so
`s = gptr()` keeps the conversation for later piping.

### D-06 System One API shape
Preliminary: `gptr("question", x, model = jev, type = ...)` returns typed
vectors: `gptr_decision` (logical + `prob`), a factor-like choice with a
probability matrix, numeric score with confidence. Vectorised over inputs with
concurrent HTTP. Abstention policy when confidence is below a threshold:
default is to return the most probable answer and record the probability;
`na_below =` opts into `NA`; `stop_below =` opts into an error. Emulated
System One through a System 2 model with structured output when no Jev key is
configured.

### D-07 Non-standard evaluation
Preliminary: base R only (`match.call`, `substitute`), symbol → name,
string → literal, `c(a, b)` of symbols supported, `!!`-style injection not
needed; a variable holding a model name is passed as `model = I(var)` or via
`model = get_model(var)`. Proposals must specify the ambiguity rule precisely
(what happens when `jev` is also a variable in scope).

### D-08 Document harness
Preliminary: generated code goes directly below the originating `gptr()` call
in a delimited block with a stable id; outputs as `#>` comments; rationale as
comments. Replay modes `live` / `replay` / `record`; non-interactive runs
default to `replay` when a recorded block exists.

### D-09 Session persistence
Preliminary: two synchronized forms. Machine form: JSONL tree in
`.gptr/sessions/` for exact resume. Human form: the runnable script/notebook.

### D-10 Workspace and global state
Preliminary: `.gptr/` in the project, created only by explicit
initialisation or interactive consent; global config, credentials and model
catalog cache under `tools::R_user_dir("gptr", ...)`.

### D-11 Permission modes
Preliminary: `manual`, `edits` (auto-approve file edits in the workspace),
`auto`, `plan` (read-only). An advisory static risk classifier labels R code;
it is documented as not being a security boundary.

### D-12 Sub-agent execution modes
Preliminary: `inline` (same process, shares memory, interleaved I/O),
`worker` (separate R process, true CPU parallelism, data serialised),
`cli` (external `claude` / `codex`).

### D-13 Concurrency engine
Open until research track 15 reports: `curl` multi handles vs `httr2`
parallel/connection APIs vs promises.

### D-14 MCP
Preliminary: own client (`processx` for stdio, `httr2` for HTTP); import
servers configured for other harnesses; MCP tools surfaced as R functions.
gptr as an MCP *server* is how CLI providers reach the live session.

### D-15 Subscription providers
Preliminary: drive the official `claude` and `codex` CLIs through `processx`.
Native OAuth only where the vendor's terms allow it (research tracks 07, 08).

### D-16 Skills, extensions, plugins
Preliminary: Agent-Skills `SKILL.md` folders; extensions are R files exporting
a function that receives the gptr API; plugins are bundles; any installed R
package may ship `inst/gptr/` content.

### D-17 Artifacts
Preliminary: Shiny app in a background R process with a data snapshot;
registry under `.gptr/artifacts/`.

### D-18 Model references and catalog
Preliminary: `provider/model` strings plus aliases; snapshot catalog shipped
in `inst/extdata`; refresh only on request into the user cache dir.

### D-19 Context management
Preliminary: provider-reported usage plus a character heuristic; automatic
compaction near the context limit; tool outputs truncated with the full text
saved to a temp file.

### D-20 Dependency budget
Preliminary Imports: `httr2`, `jsonlite`, `cli`, `processx`. Everything else
in `Suggests` and guarded by `requireNamespace()`. Proposals must list every
Import and defend it.

### D-21 Compiled code
Decided by research track 21 against the bar in REQ-01.

### D-22 Secrets
Preliminary: keys from environment variables, `.env` files loaded explicitly,
aliases mapped to canonical names (`jev-key` → `TYPESAFE_API_KEY`); secrets are
redacted from every transcript, log and error message.

### D-23 Minimum R version
Preliminary: R >= 4.1.0 (native pipe, lambda shorthand, raw strings).

### D-24 Testing strategy
Preliminary: a built-in fake provider with scripted responses; local mock HTTP
server for wire-format tests; recorded fixtures; all network and key-dependent
tests skipped on CRAN.

### D-25 Hook and event taxonomy
Open until research tracks 02 and 05 report.

### D-26 Console UX
Preliminary: `cli` for rendering; interrupt returns to the prompt without
ending the session; `!` prefix evaluates R directly; slash commands.

### D-27 knitr / Quarto integration
Open: whether to register a `gptr` chunk engine in addition to plain
`gptr()` calls inside R chunks.

### D-28 Exported API naming
Preliminary: `gptr()` is the gateway (S-1). Supporting functions carry a
`gptr_` prefix (`gptr_init()`, `gptr_config()`, `gptr_tool()`,
`gptr_models()`), which avoids collisions with other packages.


## Final decisions (design phase, 2026-09-29)

Resolved by the lead architect from proposals P-A, P-B and P-C, the three judge verdicts (requirements
`J-req`, CRAN/security `J-cran`, implementation `J-impl`) and the research. The architecture is
`03-architecture.md`; the plans are `05-plan-decomposition.md`. Two of three judges ranked P-A first, so its
lean core is the skeleton; P-C's user-facing design and P-B's plugin-enforcement mechanisms are grafted on.
Where a decision departs from all judges, the evidence is named. Section references (§) are to
`03-architecture.md`. The adversarial review of 2026-09-30 amended several decisions below; the amended text is
marked "(review)" and the full record is `06-review-resolution.md` and contract §15 (IC-32..IC-73).

### Decisions D-01..D-28

**D-01 Provider layer.** Settled by S-10: gptr's own layer on curl multi handles only; no httr2 anywhere, no R
LLM package in Imports or Suggests. httr2 blocks during the header wait and batches output (10a E1/E2), its
parallel path retries 429/503 without bound (04 §2.16), and dropping it removes 7 packages from the closure.
All proposals and judges agree. (§6.1, §9)

**D-02 Object system.** S3 classes: environments for mutable objects (session shell with a hidden data
environment, registry, API object, ctx, reactor, runs, jobs), classed lists and base-typed vectors for values.
No R6 or S7. G1 measured about 2x cheaper method calls and 13-16x cheaper creation than R6 (ratios, per its
fact-check); G3 measured 5.5 KB vs 21 KB serialised sessions; System 1 values must be base-typed for `if()`
(04). Unanimous. (§5)

**D-03 Model-visible tools.** Direct tools `r`, `read`, `edit`, `write`, plus `ask` only when a human is
present (trimmed schema, 145 tokens). `grep`, `find`, `ls` and every other capability are `gptr$` namespace
members; the `extended` preset promotes grep/find/ls per model. No shell tool, not even opt-in (S-4; G5 §8); no
todo tool (20 §4); `edit` accepts `*** Begin Patch` envelopes and `apply_patch` is v1.x. Measured: 675 tokens
for the four schemas vs 1,199 for seven (G4 §2.8); about 36 vs 328 tokens per tool as an R signature
(G1 §2.5). (§7.1)

**D-04 Evaluation environment.** `envir = parent.frame()` with an explicit override and the magrittr-mask fix
(12 §2.B4); never name `.GlobalEnv`. Inline sub-agents and forks evaluate in overlays
`new.env(parent = envir)`. No binding locks anywhere: `lockBinding()`/`unlockBinding()` makes the next in-place
edit copy (judge checks, PB-E1, P-A experiment), which was P-C's fatal flaw. A function-frame home is held only
during a run, in an environment binding reset at settlement (G3; rule R2). (§6.4)

**D-05 Return value and pipe semantics.** `gptr()` returns the session environment for every System 2 shape;
teams, fan-outs, children and replayed sessions are session kinds (P-C; P-B's `gptr_group` broke S-8).
Piping into an idle session starts a follow-up turn on the same object and file; piping into a running one
enqueues a steer and returns at once; it never forks. One queue per session is fed by the pipe, the pause
menu, `gptr_steer()` and `ctx$send()`. `gptr_fork(s, at, envir = "overlay")` is the only branch, recorded as
`fork=` in the block header. `$value` follows G3's policy: large bound objects by name and address, small ones
copied, anonymous values boxed (judge copy check: holding the value copies, holding the name does not);
`$<-` is refused and replay reads `value=` from the block header. `background = TRUE` ships as an
experimental, opt-in feature (own plan) because S-8 makes console pipe-steering of a running session a core
idea and G3 verified it end to end in terminal R; J-cran and J-impl preferred deferral, which is why it is
isolated and excluded from examples and CRAN tests. System 1 accepts a piped session through `as_state()`.
(§4.1, §5.1, §6.2)

**D-06 System 1 API.** `gptr(q, x, model = jev, choices =, levels =, threshold = 0.5, min_confidence =,
uncertain =)` returns `gptr_decision` (logical), `gptr_choice` (classed character; a factor only on request)
or `gptr_score` (double) with probabilities as attributes, vectorised on the reactor (at most 8 active, 3
bounded rounds). A factor is truthy in `if()` and `switch()` uses its integer code (04 §2.15). Abstention is
off by default; `min_confidence` + `uncertain` (NA, TRUE/FALSE, "stop", or a function that escalates) is the
INFRA-18 `na_below`/`stop_below` policy. Logical-looking labels are rejected (04 verifier). Emulation is
opt-in only, never silent (J-cran). No `decide()`/`classify()` exports (S-1). (§4.1.5, §5.6)

**D-07 Non-standard evaluation.** Base-R capture under G3's copy-safety rules, not rlang quosures. All
judges recommended `rlang::enquo()` (12 §2.D2), but G3 showed that garbage quosures keep a forwarding
wrapper's frame alive so the caller's object copies on its next edit, while base capture that forces promises
in leaf functions is copy-safe and resolves forwarded dots correctly (G3 t2b, t5; verified by its fact-check);
the architect's re-run confirmed `enquos` COPY vs `...elt` leaf in place (`final/capture_check.R`).
Resolution rule: a known identifier (alias, registered model/provider/router, mode, skill, plugin, agent) wins
over a same-named variable (as `library()` does; 10 Q4), with `!!x` and `I(x)` escapes and a one-time notice;
other bound symbols take their character value or spec object, other classes error; unknown unbound symbols
are literal names; calls are evaluated in an alias mask. (§4.1.3, §6.4 R3)

**D-08 Document harness.** Report 14's block grammar below top-level calls, with header keys `model`, `date`,
`prompt`, `args` (review), `sha`, `call`, `tokens`, `cost`, `session`, `turn`, `value`, `fork`, `plan`, `kind`,
`children` (review), `status`; replay modes `auto`/`replay`/`live`/`record`; `gptr()` never executes a recorded
block; under base `source()`/Rscript `live` downgrades to replay with a warning; replay forced under R CMD check
outside testthat, i.e. in examples (review, IC-45). (review) Replay needs no write consent (the route matches a
located block); a piped session is advanced in place; forks are bound by block id; teams, fan-outs and
block-nested calls replay from the S2 cache; recorded code drops `gptr_return()` and inspection-member calls
(IC-45..IC-49). Nested calls in loops get no block: they run live on re-source (REQ-24 allows non-determinism)
and fail with "not recorded" under `GPTR_REPLAY=replay`. Cassettes are a v1.x plugin with J-cran's HMAC and trust rules and J-impl's content keys,
because hidden recorded code was P-C's fatal flaw. Writes only to designated or confirmed documents. (§6.9.3)

**D-09 Session persistence.** Pi-v3-shaped JSONL tree, strictly append-only (compaction, rewind and checkpoints
are appended entries), open-append-close per entry or batch (review: a kept-open connection per session leaves
connections open in examples and exhausts R's 125 connections, IC-59), appends inside `suspendInterrupts()`,
torn-line recovery at resume and ps-checked pid locks (review),
redacted at ingress, in `.gptr/sessions/` (gitignored) or `tempdir()`; plus the runnable document. Sessions
hold data only; split-brain rules for detached copies (G3). Pi-readability is best effort, not a contract
(J-cran). (§6.9.2)

**D-10 Workspace and global state.** `.gptr/` only through `gptr_init(path)` (no default path: interactive
confirmation, error otherwise) or an interactive yes; creating it is consent to write, not trust. Without a
workspace, sessions, artifacts, caches and checkpoints live in `tempdir()` and the System 1 cache in memory.
User state only under `tools::R_user_dir("gptr", ...)`, small and pruned; the `.Rbuildignore` line is offered,
never written silently (13 §2.3-2.4; J-cran). (§6.9.1, §6.10)

**D-11 Permission modes.** `plan`, `manual` (default), `edits`, `auto`; risk levels 0-4 from an advisory
classifier (R, shell, SQL, Python; tables as data) documented as not a security boundary; deny > ask > modify >
allow; a throwing policy denies; project settings only tighten; level 4 and the secret guard ask even in auto.
A non-interactive ask stops the run with status `blocked` and `gptr_error_permission` naming how to allow it
(NS-12; P-A); `gptr.noninteractive_ask = "deny"` opts into denial. Plan mode runs only calls known to be read-only
in a scratch environment (review, IC-54) and hands a pending plan to the next top-level call once (P-C; IC-56).
(review) The gate fails closed without a mode policy; the permission kernel cannot be filtered out; safety options
are snapshotted per run; gptr's own configuration exports and control-plane files are a level-4 `control`
category answered only by a human (`ask_human`); unlisted functions of non-base packages are level 1 (IC-53,
IC-54). (§6.8)

**D-12 Sub-agent backends.** `backend = "auto"` everywhere: inline (overlay, zero-copy reads, no locks, own RNG
stream), except `cli` for CLI-only models; `worker` through callr with `user_profile = FALSE`, an empty
`R_ENVIRON_USER`/`R_PROFILE_USER` (callr otherwise re-injects `~/.Renviron` keys, G6 fact-check; review: every
child profile gets them, IC-60) and NA-unset secrets, inheriting the session's registry records (review, IC-69);
`cli` for claude/codex. Limits: 8 tasks per team or fan-out started by model code (review: user fan-outs queue
every element, IC-39), 8 inline / 4 CLI / `min(4, cores - 1)` workers, every child pool 2 when
`_R_CHECK_PACKAGE_NAME_` is set (13 C-40); depth 1 (configurable to 2). `fork` and mirai/mori are v1.x.
Five inline agents took 5.2 s vs 14.0 s sequentially (15 §2.3). (§6.13)

**D-13 Concurrency engine.** One gptr-owned process reactor: curl multi with `pipewait = 0L` and
`followlocation = 0L` (review), `processx::poll()` over curl fds and child pipes, timers, one R-tool FIFO,
admission control, re-entrant for nested calls with `allow_runs` (J-impl), which defaults to none inside a run
(review); `later::run_now(0)` only in the outermost pump (or one waiting for a served CLI child) to service httpuv
servers and experimental background sessions (review, IC-57). No coro or promises. (15 §4.1-4.2; §6.1)

**D-14 MCP.** Own client for both protocol eras (probe, era cached per server), stdio through the G5 process
engine (`.cmd` shims via `cmd.exe /d /c call` with metacharacter refusal) and Streamable HTTP on the reactor;
default exposure `r` as `gptr$mcp$<server>$<tool>()` with a 1,500-token signature catalog; other harnesses'
configs listed read-only and imported on request; project configs only when trusted. gptr as a server: the
in-process `sdk` transport for the claude CLI, and a loopback HTTP server (`gptr_mcp_serve()`: 127.0.0.1, an
RNG-free port, one 192-bit token per client bound to its session (review, IC-58), Origin check, permission gate,
tool timeout >= 3,600 s) so Codex and external agents reach the live session; this fixes P-A's "Codex cannot see
live R" flaw. (16 §4; §6.14)

**D-15 Subscription providers.** Claude plan: the user's unmodified `claude` CLI (stream-json, control
protocol, in-process sdk MCP), experimental and opt-in with a one-time notice, neutral provider id
`claude-cli` with alias `claude_code`, minimum-version probe, billing-switch variables removed with a warning,
never touching Claude credentials; the maintainer asks Anthropic before advertising it (07 §2.18 policy
UNCERTAIN). ChatGPT plan: `codex exec --json --ignore-user-config --skip-git-repo-check -m <id> -C <wd>` with the
MCP server marked approved and required, the prompt on stdin and live R through the in-session MCP server; every
mode except `auto` runs Codex's read-only sandbox (review, IC-65). Sign in with ChatGPT and the Codex app-server are v1.x plugins (preview never run end
to end; experimental schema drift; 08; J-cran, J-impl). Never port Pi's legacy Codex backend. (§8.3)

**D-16 Skills, extensions, plugins.** Agent Skills folders; extensions are `function(gptr)` factories;
plugins are R packages or directories with `inst/gptr/plugin.json` (and `Config/gptr/plugin` in DESCRIPTION),
discovered, never self-registered in `.onLoad` (13 C-29), activated lazily with `declarations` so the cached
prefix is stable, loaded transactionally with rollback; `.claude-plugin` bundles consumed for skills,
commands, agents and MCP. Every built-in is a `builtin_<name>()` factory using only the public API, enforced by
a codetools layering test (P-B). (G1 §4.4; §11)

**D-17 Artifacts.** Shiny apps: the model writes `<root>/artifacts/<id>/app.R` (a 124-token section and the
`shiny-bslib` skill instead of an artifact tool) and launches it with `gptr$app(id, data =)`; immutable `vNNN/`
snapshots with data through the leaf `saveRDS(ascii = FALSE)` wrapper; a supervised `callr::r_bg` child with a
secret-free environment, a random loopback port and a parent-PID watchdog; validation ladder parse, launch,
HTTP 200, optional chromote check and screenshot. `.gptr/artifacts/marker-explorer/app.R` is literal (NS-8).
Shiny costs 2.35x fewer tokens than HTML/JS (G2 (a)); HTML inside Shiny is the fallback (S-5). (§6.15)

**D-18 Model references and catalog.** `provider/id[:thinking]` plus dynamic aliases; a pruned models.dev
snapshot (about 51 KB) with dated price tiers in `inst/extdata`; refresh only on request into `R_user_dir()`
with ETag; canonical quoted ids written into documents; default model from the first available route
(Anthropic key -> `anthropic/claude-sonnet-5-5`). (09 §4; §8.4)

**D-19 Context management.** Provider usage plus G2's class-aware estimator (median error 11.4% vs 43% for
chars/4) with an EWMA provider multiplier; compaction at `min(G4 threshold, window - max(16384, max_output +
2 * r_cap), 200k)` with the cold rule, an in-conversation checkpoint and no in-place micro-compaction (+32% in
G4); `r` results capped at about 4,000 tokens (head 40% / tail 60%, spill file, `gptr$out(id)`); read line
numbers off; the tail TTL switches to 1 h after an inter-request gap over 240 s (G4's adaptive rule was 33%
worse in the fast loop per its fact-check). (§6.11, §12)

**D-20 Dependency budget.** Imports: jsonlite, curl, processx, callr, rlang, cli, yaml, ps (8; review: ps for pid
liveness, already in the closure through processx, IC-59; closure 9, 10 with callr 3.8.0's otel) plus base
methods, stats, tools, utils, grDevices, graphics; not `parallel` (review: RNG streams are swapped without it,
IC-61). openssl, httpuv and later are
Suggests (only opt-in OAuth, the MCP server and background sessions need them). Full Suggests list in §9.2;
no R LLM package anywhere. (J-cran and J-impl verified closures; §9)

**D-21 Compiled code.** None in v1 (`NeedsCompilation: no`); report 21's watch list and procedure stand. No hot
path met REQ-01's bar (21 and its verifier). (§9.3)

**D-22 Secrets.** G6 in full: vault and origin-bound handles; own `.env` parser with the `jev-key` ->
`TYPESAFE_API_KEY` alias table; one ingress redactor at every sink with sink profiles; credential store
`auth.json` (0600); child-environment profiles (complete vectors) with empty `R_ENVIRON_USER`/`R_PROFILE_USER` in
every profile and G6 §3.7's CLI removal lists (review, IC-60, IC-65); a secret guard in the classifier; never
reading other harnesses' credential files; `gptr_scrub()` and the late-registration warning restored from G6 §4.7;
child logs persisted only through the redactor; no redirects followed (review, IC-64, IC-70). Plus the hard rule
that untrusted text is never a cli/glue format string (J-cran reproduced code execution through
`cli::cli_text(reply)`). (§6.3, §6.5)

**D-23 Minimum R version.** `Depends: R (>= 4.2.0)`, proven by an oldrel-4 CI job (UTF-8 native on current
Windows, the `_` placeholder; 13 §2.7). Unanimous. (§9)

**D-24 Testing strategy.** Exported fake provider for every example; base-R mock SSE server (processx child,
skip on CRAN); wire fixtures replayed through the real parsers; `gptr_check()` conformance; fake CLIs; a pure-R
MCP fixture server for both eras; fresh-process tracemem suites for every entry point incl. function-frame
homes, on R-release and R-devel; the 20-turn prefix test and the offline prefix-budget test (CRAN-safe); the
codetools layering test; lint rules for the invariants; ported report-02 and Pi oracles; secrets and injection
end-to-end tests; an INFRA acceptance table; CI with check-standard, oldrel-4, no-suggests, `LC_ALL=C` and
Windows from M0; live tests only under `GPTR_LIVE_TESTS=true`. (§3.4, §6.18)

**D-25 Hook and event taxonomy.** Pi-derived canonical names with Pi's dispatch semantics plus gptr events
(`permission_request`, `decision`, `document_write`, `route`, `model_select`, `subagent_*`, `artifact_*`,
`usage`, `budget_near`, `budget_exceeded`, `cache_break`, `bridge_call`, `checkpoint`, `session_before_tree`,
`session_tree`); `tool_call`, `permission_request` and `document_write` fail closed; handlers return patches;
Claude/Codex names only through the v1.x hook importer's alias map. (G1 §3.2; §5.4)

**D-26 Console UX.** cli rendering with a chunk-invariant markdown stream and rule C1; Ctrl-C pause menu
(steer, follow-up, continue, abort, background) through the `resume` restart feeding the same queue as the
pipe, with an abort-only fallback where unverified; `!` and `!!`; slash commands incl. `/undo`, `/redo`,
`/rewind`, `/context`; UI backends `console`, `none`, `scripted`, `rstudio`; never `askYesNo()` for
permissions. (18 §4; §6.17)

**D-27 knitr / Quarto.** No `{gptr}` chunk engine in v1 (it relaxes S-2; 14 §4.6); `gptr()` in R chunks with
`knit_print` is the supported path; replay forced in R CMD check's examples (review: not in its tests, and
vignettes are precomputed, IC-45). J-cran and J-impl
deferred it; J-req's opt-in plugin becomes v1.x. (§6.9.3)

**D-28 Exported API naming.** 63 exports (IC-01 added `gptr_preimage()`; review: `gptr_map()` is internal because
S-1 keeps one gateway, and `gptr_scrub()` is new, IC-36, IC-70): `gptr` plus `gptr_*` (P-A's small surface plus the
SDK verbs and constructors needed for S-11), none colliding (G1 §4.7). The tools-as-functions dispatcher is the classed-closure
gateway namespace `gptr$...` (passes R CMD check, G5; one name for gateway, tools, bridges and MCP); `agent()`
exists only in the `agents =` mask; no `tools`, `mcp`, `decide` or unprefixed exports. Other kinds use
`gptr_spec(kind, ...)` and the factory API's `register_<kind>()` sugar. (§4)

### Cross-track conflicts C-1..C-33 (the known conflicts 1-18 are C-1..C-18)

**C-1 R6 vs S3 + environments.** S3 + environments (D-02). R6 arrives transitively through processx and is
not used. (G1, G3)

**C-2 HTTP transport and SSE parsing.** One curl-multi reactor for every HTTP request (providers, System 1,
MCP HTTP, OAuth, catalog refresh) with gptr's own vectorised byte-level SSE/NDJSON splitter that flushes a final
unterminated event (21 §2.6: about 17x faster than `resp_stream_sse()`, which drops that event per the 08
verifier). No httr2, so its minimum-version disagreement disappears. (D-01, D-13)

**C-3 Imports budget.** Eight Imports: jsonlite, curl, processx, callr, rlang, cli, yaml, ps (review, IC-59).
openssl, later and httpuv in Suggests; R6 not used; httr2 excluded. yaml in Imports because skills are core and a hand parser lost
real skills (05). (D-20)

**C-4 NSE capture and ambiguity rule.** Base-R capture under G3's rules (D-07 overturns the judges' rlang
choice with G3's verified evidence); a known identifier wins over a same-named variable with `!!`/`I()`
escapes. 09's and 05's "bound variable wins" rules are rejected because attached packages exporting `codex` or
`plan` would hijack identifiers (10 Q4).

**C-5 Evaluator and plot capture.** Hand-rolled evaluator (12 §2.A2: evaluate's sink, device and
sticky-reference defects); evaluate is not a dependency. Plots for the model at 768x512 res 120 (532 tokens,
legible per G2); larger views on request with `gptr$plot()`; artifact screenshots at 1000x700.

**C-6 Tool surface, R tool name, todo, edit result.** Four direct tools plus `ask`; the tool is `r`; no todo
tool; `apply_patch` v1.x with patch envelopes accepted by `edit`; edit results are Pi's message, with a diff of
at most 400 tokens only when the fuzzy fallback or normalisation changed the match. (D-03)

**C-7 Dispatcher and MCP naming.** The gateway namespace `gptr$...`; MCP tools under `gptr$mcp$<server>$<tool>()`;
no `tools` object (base package name) and no `mcp` export (collision with mcptools); member access has no side
effects; an evaluator shim resolves `gptr` for model code when the package is not attached. (D-28)

**C-8 Default sub-agent backend and limits.** `auto` = inline except CLI-only models; worker via callr with a
scrubbed environment; limits and depth of D-12; naming "worker". (15)

**C-9 System 1 API shape and transport.** Classed-character choices; single gateway; `min_confidence` +
`uncertain`; requests on the reactor with bounded rounds, never `req_perform_parallel`. (D-06)

**C-10 Return value.** The session object itself with `$value` by name (D-05); report 12's `gptr_result` fields
become session accessors; report 15's result lists become team and fan-out sessions.

**C-11 Claude plan bridge.** Unmodified CLI with stream-json, the control protocol and the in-process `sdk`
MCP server as the only v1 transport (no port, no token; the httpuv fallback is not used for claude, avoiding the
60 s per-request timer issue); opt-in with a notice; provider id `claude-cli`, alias `claude_code`; name use
flagged for the maintainer. (D-15; 07 and its verifier)

**C-12 ChatGPT plan route.** `codex exec --json` plus the in-session HTTP MCP server in v1; Sign in with ChatGPT
and the app-server as v1.x plugins after a live end-to-end test and a schema probe. (D-15; 08)

**C-13 MCP protocol eras.** Speak both; `server/discover` probe with 5 s timeout, fallback to `initialize`,
era cached per server; fixtures per era; the versioning page re-checked each release. (16 §4)

**C-14 Session format vs compaction.** Strictly append-only Pi-v3-shaped tree; failed attempts projected out,
never edited; compaction appended as an in-conversation checkpoint; no in-place micro-compaction (preserved
thinking and caches; G4 §2.10). (D-09, D-19)

**C-15 Workspace consent and locations.** `gptr_init(path)` with no default and interactive confirmation (NS-9's
`gptr_init()` works at the console); tempdir otherwise; artifacts under `.gptr/artifacts/` when a workspace
exists (NS-8 literal), else `tempdir()/gptr`; the System 1 cache in memory before init; trust recorded
separately with `gptr_trust()`. (D-10)

**C-16 Steering channels.** One in-memory queue per session with steer and follow-up lists; producers: the
pipe into a running session, the pause menu, `gptr_steer()`, `ctx$send()` and sibling agents; delivery after
the complete tool-result message (INFRA-12). No file inbox in core (an injection path from shared folders,
J-cran); the httpuv side channel is not a steering channel. (§6.2)

**C-17 Script-as-history under Rscript and source().** Deferred Rscript writes through
`reg.finalizer(onexit = TRUE)` with a crash sidecar; srcref validated by content, then the `source()` frame read
inside `tryCatch` with an off switch (CRAN grey zone per 14's verifier), then content and ordinal matching;
`live` only via `gptr_source()`, knitr or line-by-line IDE runs, otherwise replay with a warning. (D-08)

**C-18 Copy safety vs snapshots, guards and hashing.** A cross-layer invariant with rules R1-R10 (§6.4): no
held user objects or frames (values by name, frames only in reset environment bindings, no weak references to
frames), base-R capture, leaf introspection, no binding locks, no `mget()` snapshots (G7 pre-images released
with `rm()` and defused), `serialize(ascii = FALSE)` everywhere, sampled fingerprints plus static assignment
targets instead of full hashes; a fresh-process tracemem suite on R-release and R-devel, including tool code in
function-frame homes (G3 fact-check). Evidence: judge checks, G3, G7, `final/frame_hold_check.R`.

**C-19 System 1 decisions in the history document.** Calls inside control flow write nothing (the user's
control-flow code is the REQ-26(c) record, 14 item 14); decisions are cached per element and recorded as
`gptr.decision` entries when a session is active; a top-level System 1 statement gets a one-line `#>` summary
block (04 wanted recording; P-A). (§6.9.3)

**C-20 Project instructions placement and precedence.** User-role data in the first user message with a 1 h
cache anchor: AGENTS.md and CLAUDE.md from root to cwd, then `.gptr/vignette.Rmd` last and additive (never
executed, YAML and HTML comments stripped); precedence stated once in the frozen `<context>` section; the
system prompt is frozen at session start (07, G4 §4.2). Context files are data; SYSTEM and APPEND_SYSTEM files
are trust-gated. (review) Their *authority* is trust-gated: in an untrusted project they render
`trusted="false"` as information, not commands, and non-interactive `auto`/`edits` runs omit them (IC-52).
(§6.11, §7.4)

**C-21 Hook and event taxonomy.** Pi-derived names plus gptr events, fail-closed trio, patch returns (D-25);
20's Claude/Codex names only through the importer.

**C-22 Permission mode names and plan mode.** `plan`/`manual`/`edits`/`auto` (18, D-11, north star); plan mode
evaluates level-1 R in a scratch environment, denies writes, ends with a `<proposed_plan>` saved under
`plans/` and kept as the pending plan; without a UI an ask stops the run (NS-12) rather than silently denying.
(§6.8.5)

**C-23 Compaction thresholds and token estimation.** G4's threshold combined with G2's output reserve and a
200k soft cap, the cold rule, and G2's class-aware estimator (printed R at 2.13 chars per token) with an EWMA
multiplier; Pi's 16,384 reserve and chars/4 are superseded. (D-19)

**C-24 Skill catalog budget and activation.** Compact catalog (descriptions at most 160 characters, 33-50
tokens per skill) within 1,500 tokens with least-recently-used trimming and `gptr$search()` beyond it;
activation through `read` (no skill tool whose enum would change the cached tool array); `skills =` preloads
bodies as `<skill_content>`. (G2 (b), 16; §7.3)

**C-25 Bash mapping and agent-file directories.** Bash and PowerShell in foreign agent definitions map to `r`
(15, 16, G5; S-4), never to a shell tool; directories read: `.gptr/agents`, `.claude/agents`, `.codex/agents`
(markdown), `.pi/agents`, user-level equivalents and packages' `inst/gptr/agents`. (§11.1)

**C-26 Opt-in shell tool vs S-4.** No shell tool in gptr, not even opt-in; `gptr$sh()` and the other bridges
cover the need (G5 §8: 22.9x fewer tokens R-composed than a bash tool); a third-party plugin may add one only by
routing through `gptr$sh()` and the `r` pipeline. (D-03)

**C-27 Exported names vs collisions.** Only `gptr` and `gptr_*` (D-28); report 16's `mcp_*`, 17's `artifact*`,
04's `decide/classify/rate/judge` and 06's `tools` become namespace members, `gptr_*` exports or internal.

**C-28 knitr chunk engine.** Not in v1 (D-27); replay-only behaviour would be required if it is added in v1.x.

**C-29 File-tool implementation recipes.** grep: `readBin` per file, `grepRaw(fixed = TRUE)` prefilter for
literals, whole-file `(?m)` PCRE prefilter for regex, NUL sniff, early stop, never per-file `readLines` (21
§2.1), with 11's `readChar` batching for many small files; read: raw newline index up to 16 MiB, streaming
index above, cached sparse index above 20 MB (11 + 21); diff: patience anchors plus Myers capped at D = 256,
no diffobj (21 §2.3); find: Pi's `**/` prefix rule (11 verifier). (P-C C-29)

**C-30 One event loop for reactor, later and httpuv.** The outermost reactor pump calls `later::run_now(0)`
each iteration when later is loaded (servicing `gptr_mcp_serve()` and OAuth callbacks, never `httpuv::service()`);
nested pumps do not, unless they wait for a served CLI child (review, IC-57); background sessions are pumped by a
`later` timer that is a no-op while the reactor is on the stack (no `later_fd`, which LIKELY cannot watch processx
pipes on Windows: inferred from its documentation, untested, per the 15 fact-check); core flows never require
later. (§6.1-6.2)

**C-31 S2 cache committed vs privacy.** S2 answer text gitignored by default and redacted at ingress; the S1
cache (salted input hashes, question hashes and answers only; review, IC-70) committed by default; console
transcripts gitignored by default (review). (§6.9.3)

**C-32 Default models.** First available route: Anthropic -> `anthropic/claude-sonnet-5-5` (the north-star
banner), OpenAI -> `openai/gpt-6-sol`, Gemini -> `google/gemini-3.8-flash`, else a detected CLI; aliases resolve
to full ids and CLI invocations always pass full ids (07). (§8.4)

**C-33 Retry policy constants.** Transport: retry 408/409/429/5xx/529 and network errors before the first
committed delta, `0.5 s * 2^i` with time-derived jitter (never the RNG), cap 8 s, at most 4 attempts, Retry-After
honoured up to 60 s then fail fast, spend-cap 429 never retried (10a INFRA-06, 07); agent level: 2 retries of
classified transient errors after committed deltas (02); System 1: 3 bounded rounds resubmitting failed
elements only (04 §4.7). (§6.1)

### Review amendments (2026-09-30)

An adversarial review (requirements, CRAN/Windows, consistency, research fidelity, plugins and tokens, safety)
raised 144 issues. All were verified as valid; 139 were applied as proposed or with an equivalent alternative and
5 were applied in part, with one sub-proposal declined for a stated reason (`06-review-resolution.md`). The
decisions that changed, with their contract ids (`04-interface-contract.md` §15):

| Area | Decision | IC |
|---|---|---|
| Build | `R/aaa-state.R` holds `the`, `on_load()` and the service table and collates first, because top-level package code runs at install time in collation order | IC-32 |
| Layering | a function-level kernel SDK allowlist; L1 adapters use injected callbacks; the layering test parses `R/` | IC-33 |
| Services | complete service list, owned by built-ins, replaceable through an experimental `service` kind | IC-34 |
| Ownership | `gptr_prob()` to P13, gateway methods to P08, `gptr$out()` to P10 only, `gptr_jobs()` to P04, `gptr_map()` internal, `gptr_scrub()` new; 63 exports | IC-36, IC-70 |
| Tools | one spec per capability with direct and member forms; reserved member names; required plugin namespaces | IC-37 |
| Context | placement `both` so `<attached>` reaches the first message; unchanged turn blocks skipped | IC-38 |
| Gateway | team and fan-out before nested; `max_tasks` only for model-issued fan-outs; continuation environment precedence; symbol dots not forced; normalised skill, plugin and agent names; namespaced `.opts` | IC-39..IC-44 |
| Documents | replay by located block without consent; `args=` freshness; replay in place; forks bound by block id; team, fan-out and block-nested recording; stripped recorded code; transcripts as pipe chains; Jupyter pending blocks; durable sidecars | IC-45..IC-51 |
| Safety | settings that decide permissions live outside the project tree; trust-gated instruction authority and trust fingerprints; fail-closed, non-removable permission kernel with `ask_human` and an option snapshot; a `control` risk category; known-read-only plan mode; relays by source; stricter plan hand-off | IC-52..IC-56 |
| Runtime | reactor depth and `later::run_now(0)` in the outermost pump; one MCP token per client; open-append-close store with ps-checked locks; complete child environments with empty `R_ENVIRON_USER` everywhere, UTF-8 pipes, non-blocking stdin, supervision by default; RNG untouched (`rng_swap()`, RNG-free ports); `as_utf8()` at ingress; Windows homes and reserved names; no redirects; SSE per specification | IC-57..IC-64 |
| CLI routes | claude and codex argv corrected (single gate, `--skip-git-repo-check`, `-m`, `-C`, approved MCP), read-only sandbox except `auto`, billing checks, discovery beyond PATH | IC-65 |
| Budgets | default ceiling per top-level call, hierarchical budgets, nested-call and System 1 element caps | IC-66 |
| Evaluator | `withVisible()` results cleared; `pdf(NULL)` capture; at most 3 images per result; no `str()` in prompts | IC-67 |
| Tokens | prompt text composed by owners; `r` schema variants; skill pseudo-paths; new measured baselines (1,271 / 2,360 / 2,844 / 2,987); CI token ratchet from M1; release live calibration | IC-68, IC-73 |
| Extension API | router contract and dispatch; `ctx$set_model()`, `add_tools()`, `tokens()`, `eval()`, `describe()`; tool `render`; kinds `preset`, `risk_rule`, `renderer`, `search_source`, `store`, `evaluator`, `service` (38 in all); per-record overrides; session-scoped extensions; workers inherit the registry | IC-69 |
| Release | DESCRIPTION authors with `cph`, `Copyright`, `VignetteBuilder` added by P25; no NOTE expected apart from the maintainer line; lint configuration and conventions corrected | IC-72 |

## Local-provider amendment (2026-10-03)

**D-29 / IC-74: first-class local conversation and decisions.** The maintainer
requires Ollama support for ordinary LLMs and Clef/Clef Flash native typed
decisions, including images. `07-local-ollama.md` fixes mixed-model routing,
the `ollama-system-one` adapter, no-key local inference, local-only policy,
calibration provenance and acceptance. This supersedes Jev-only assumptions in
D-06 and later reconciliations; it does not remove hosted Jev or implement code.

Publication claims must compare against capable persistent R/MCP/notebook
alternatives. In-memory execution is not unique by itself; quality-adjusted
token/cost savings and fresh-session reproducibility require live evaluation.

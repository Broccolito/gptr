# gptr revamp — Vision Brief (source of truth for requirements)

Date: 2026-09-29. Author of requirements: Wanjun Gu (package maintainer).
Sources: the maintainer's written request + the recorded design discussion
(`gptr-discussion.txt`). This file distills both. Requirement IDs (`REQ-nn`) are
referenced by the design spec and the implementation plans for coverage checks.

## One-paragraph pitch

`gptr` becomes an **atomic, cross-platform AI agent harness that lives inside R**.
It is an ordinary CRAN package: `install.packages("gptr")` and it works on any
machine that runs R (Windows, macOS, Linux). The agent operates **on the live R
session** — the objects already in memory — instead of writing a script and
re-running it from scratch. The same `peter()` function is both an interactive
chat in the R console and a programmable function you put in scripts, loops and
`if` statements. It unifies slow "System 2" LLMs (Claude, GPT, Gemini, ...) with
fast "System 1" typed-decision models (hosted Jev and local Ollama Clef/Clef Flash). The script/notebook
the user is working in *is* the harness and *is* the history.

## Why (the three headline benefits)

1. **In-memory object compute.** A 5 GB Seurat object that takes 3–5 minutes to
   load is loaded once. The agent evaluates code in the user's environment, makes
   a mistake, fixes it, and re-runs — without reloading. Script-restarting workflows
   lose this state; other agents can also use persistent interpreters or R/MCP
   tools, so evaluation must include those capable baselines (for example,
   [btw](https://posit-dev.github.io/btw/) and
   [TaskWeaver](https://microsoft.github.io/TaskWeaver/)). gptr is native: it is a function running
   in the session, so objects it creates are injected into the environment and
   the user's subsequent code just sees them.
2. **System 1 + System 2 in one harness.** Generative LLMs for open-ended work;
   Jev-style typed probabilistic decision models for fast judgments
   (yes/no, pick-one-of-N, routing), usable directly inside `if`, `for`, `while`.
3. **The whole R ecosystem.** All tools are R functions; artifacts are Shiny apps;
   documents are R scripts / R Markdown / Quarto / Jupyter.

## Requirements

### Platform and packaging
- **REQ-01** R implementation. No Node/Python runtime dependency for core
  functionality. Everything is written in R by default.
  **Rcpp exception (maintainer amendment, 2026-09-29):** C++ via the `Rcpp`
  package counts as R integration and is permitted, but *only* for hot paths
  where performance absolutely matters and a measured benchmark shows that R
  (base or an optional accelerator package) is not good enough. Every Rcpp
  routine must (a) be justified by a recorded benchmark, (b) have a pure-R
  reference implementation with identical behaviour that is used in tests to
  cross-check it, and (c) be small and dependency-free (no external system
  libraries), so the package still builds on Windows, macOS and Linux with
  the standard toolchain and is distributed as CRAN binaries.
- **REQ-02** CRAN-compliant: passes `R CMD check --as-cran`, obeys the CRAN
  Repository Policy (file system writes, global environment, network use in
  examples/tests, cores, etc.).
- **REQ-03** Cross-platform: Windows, macOS, Linux. No tool may assume a POSIX
  shell. Works in plain terminal R, RStudio, Positron, `Rscript`, knitr/Quarto
  rendering, and Jupyter (IRkernel).
- **REQ-04** Purge the existing package API (`get_response()`,
  `dataframe_to_text()`); this is a complete revamp, nothing is kept.

### Core tools (all implemented in R)
- **REQ-05** File read, file write.
- **REQ-06** File edit (exact-match replace / multi-edit, with diff output).
- **REQ-07** grep (content search) implemented in R.
- **REQ-08** Find / list / **sort** capabilities implemented in R (file
  discovery with glob patterns, directory listing, sorting of results by name,
  time, size, relevance).
- **REQ-09** An **R code execution tool** that replaces Pi's `bash`: the model
  runs arbitrary R code in the live session environment. Shell access, when
  needed, goes through R (`system2()` / `processx`), never through an assumed
  bash.
- **REQ-10** Keep the exposed tool surface minimal, in the spirit of Pi
  (read / write / edit / bash → read / write / edit / R). Recommend optional
  high-performance packages for data work (e.g. data.table, arrow, duckdb,
  collapse, qs2, vroom, stringi) and use them opportunistically when installed,
  falling back to base R.

### Models, providers, routing (all in R)
- **REQ-40** **gptr owns its LLM infrastructure** (maintainer, 2026-09-29).
  The existing R LLM packages (ellmer, tidyllm, chattr, gptstudio, mall,
  btw, mcptools, openai, rollama, corteza, aisdk, agenticr, ...) were mostly not
  built for agentic use, and their infrastructure does not suit this design.
  gptr therefore designs its own sending/receiving infrastructure — transport,
  streaming and interrupts, provider adapters, message and tool-call model,
  sessions, concurrency — to **supersede** theirs. It may borrow ideas from
  them, but it does not depend on, wrap, or inherit any of them: none of them
  appears in Imports, and no compatibility bridge is part of v1.
- **REQ-11** Native HTTP API providers written in R: Anthropic, OpenAI,
  Google Gemini, OpenAI-compatible endpoints (OpenRouter, Ollama, Groq, ...),
  with streaming, tool calling, images, reasoning/thinking controls, usage and
  cost accounting.
- **REQ-12** Subscription ("plan") providers: use the user's Claude plan through
  Claude Code and the user's ChatGPT plan through Codex.
- **REQ-13** System 1 provider: TypeSafe AI **Jev**
  (<https://typesafe.ai/blog/introducing-system-one-models-and-jev>). API key
  expected in a `.env` file. The maintainer's copy is
  `.secrets/jev-key.env` relative to the repository root and holds one variable named
  `jev-key` (a non-standard name containing a hyphen). The conventional
  variable is `TYPESAFE_API_KEY` (the name Pi uses), so the `.env` loader must
  accept aliases such as `jev-key` / `JEV_API_KEY` and map them onto it. The
  key must never be written into scripts, histories, logs or reports.
- **REQ-13a** Local Ollama is first-class for conversational LLMs and native
  typed decision models. Clef (27B) and Clef Flash (9B) support text and images
  through Ollama >= 0.35.1. Native decisions use `/v1/systemone`, not chat JSON
  emulation. No cloud key or silent cloud fallback is required. Model-level
  capability discovery, local-only operation, provenance and acceptance are
  specified in `07-local-ollama.md` and contract IC-74.
- **REQ-14** Model routing: choose model per call / per agent / per task;
  switch models mid-conversation; cross-provider conversation hand-off.
- **REQ-15** Provider setup UX: configure providers, keys and defaults from R.

### The `peter()` function (formerly `gptr()`)

Maintainer decision 2026-10-05 (D-135): the package stays `gptr`; the entry point is `peter()`
and its namespace `peter$...`; other exports keep the `gptr_` prefix. The name honours Peter
Cathcart Wason, whose work on reasoning with Jonathan Evans framed the dual-process ("System 1"
and "System 2") view that gptr combines in one agent flow, and Peter Naur of the Backus-Naur
form, in the spirit of recording agent sessions as readable, replayable R scripts, R Markdown,
Quarto documents and Jupyter notebooks.

`peter(...)` is the **single gateway** to the harness (maintainer decision,
2026-09-29): one variadic function that either launches the interactive
session or acts as the function that receives a prompt. **Prompts are always
quoted strings**; an unquoted natural-language prompt is not valid R syntax and
is not supported.
- **REQ-16** `peter()` with no prompt (or in interactive use) starts an
  **interactive chat session in the R console**.
- **REQ-17** `peter("prompt", model =, skills =, extensions =, plugins =, ...)`
  is a **programmatic prompting function** that runs the agent loop and returns
  a value.
- **REQ-18** **The pipe is the steering operator** (maintainer, restated
  2026-09-29 as a core idea): `peter("prompt 1") |> peter("steering prompt") |>
  peter("prompt 3")`. What flows through `|>` is **the one object that
  represents the agent session**, and each piped `peter("...")` adds a steering
  message or an additional prompt **to that same session object** (same
  history, same model state, same workspace), not a new, loosely linked
  conversation. Forking a session into a separate branch must be explicit.
  The goal is that a `.R` file expresses an agent workflow seamlessly, reading
  almost like ordinary R code: natural-language prompts, concrete R functions,
  conditional statements, loops and System 1 (Jev) typed outputs blended in
  one script, with `|>` chains showing how the agent was steered.
- **REQ-19** R-native ergonomics via non-standard evaluation, in the way
  `library(pkg)` needs no quotes: bare names accepted for **identifiers**
  (models, skills, extensions, plugins, session objects). This applies to
  identifiers only; the prompt itself stays a quoted string.
- **REQ-20** System 1 calls return **typed R values** (logical, factor/choice,
  numeric, with calibrated probabilities as attributes) and are **vectorised**,
  so they work as conditions: `if (peter(model = jev, ...))`, inside `for` /
  `while`, and over a vector of inputs.

### In-memory / environment integration
- **REQ-21** The agent can inspect the session: list objects, structure,
  summaries, sizes, classes — cheaply and safely for very large objects.
- **REQ-22** The agent evaluates code in the caller's environment (or an
  explicitly supplied one); objects it creates persist for the user.
- **REQ-23** Output capture: printed output, messages, warnings, errors, and
  plots are captured and fed back to the model (plots as images for vision
  models).

### Script-as-harness, script-as-history
- **REQ-24** The session history is a **runnable document**: `.R`, `.Rmd`,
  `.qmd`, or `.ipynb`. Re-running it replays the workflow (modulo model
  non-determinism).
- **REQ-25** The harness maintains that document **in real time** during an
  interactive session, and also works when a script containing `peter()` calls is
  sourced / rendered non-interactively.
- **REQ-26** Documents mix three kinds of content: (a) concrete R code
  (ggplot, servers, data steps) written by the agent; (b) natural-language
  prompts wrapped in `peter()`; (c) System 1 decisions wrapped in control flow.
  Key outputs are recorded as comments; key modelling decisions are documented
  in the file. The agent can go back and edit earlier code in the document.
- **REQ-27** Workspace directory `.gptr/` created on initialisation, holding
  `vignette.Rmd` (the project-instructions file — the analogue of `CLAUDE.md` /
  `AGENTS.md`, human-readable and renderable to HTML), skills, preferences,
  session data.

### Extensibility
- **REQ-28** Skills (Agent-Skills style `SKILL.md` with progressive disclosure).
- **REQ-29** Extensions / plugins written in R (register tools, commands,
  hooks, providers).
- **REQ-30** MCP client support (stdio and HTTP transports), harness-agnostic:
  MCP servers configured for other agents should be usable.
- **REQ-31** Editable system prompt; prompt templates; slash commands.

- **REQ-41** **Everything can be a plugin** (maintainer, 2026-09-29). One of
  Pi's biggest advantages is how expandable it is; gptr must be at least as
  expandable. Every capability category is registered through the same public,
  documented, versioned extension API that the built-ins themselves use:
  providers (native API, subscription CLI, System 1), model routers, tools,
  MCP servers, skills, prompt templates, slash commands, hooks/events,
  permission policies, context/environment describers, compaction strategies,
  document formats and history writers, artifact types, sub-agent backends and
  agent definitions, and front ends (console, Shiny, knitr). Built-in features
  are implemented as plugins on that API. Any R package can ship plugins, and
  third parties can build whole agentic layers (orchestrators, domain agents,
  workflow engines) on top of gptr's public API without touching its internals.

### Token efficiency
- **REQ-42** **Token efficiency is a first-class design criterion**
  (maintainer, 2026-09-29). R's semantic compression is a core reason for
  building the harness in R, and the design must exploit it and measure it:
  - *Compact artifacts and code:* prefer R and Shiny, whose code is far shorter
    than equivalent HTML/JS, and steer the model towards concise idiomatic R.
  - *In-memory compute:* keep data in the session and refer to objects by name
    with compact, budgeted descriptions; never serialise large data into the
    context when R can compute on it and return a small result.
  - *Composition over round-trips:* let one R evaluation compose many
    operations (tools, MCP tools and sub-agents callable as R functions) instead
    of many model-visible tool calls.
  - *R as token-efficient glue:* R calls other languages and programs (shell
    and bash scripts through `system2()`/processx, Python via reticulate, SQL via
    DBI, knitr language engines) through compact helpers, so polyglot work stays
    cheap without a separate bash tool.
  - *Lean context:* small tool schemas and system prompt, deferred loading of
    rarely used tools/skills/MCP tools, truncated tool output with spill files,
    append-only context that keeps provider prompt caches warm, compaction.
  - *Cheap decisions:* System 1 models for judgements instead of System 2 calls.
  - *Accounting:* per-session token/cost accounting with estimates calibrated
    for R output, budgets, and a token-efficiency benchmark suite over the
    north-star tasks, so regressions are visible.

### Agents and orchestration
- **REQ-32** Sub-agents: the harness can spawn sub-agents, each with its own
  context, model and tools.
- **REQ-33** Parallel execution: multiple sub-agents / runtimes at once to finish
  faster.
- **REQ-34** Cross-LLM collaboration: different models working on one task
  (e.g. planner + implementer + reviewer from different providers).
- **REQ-35** Agent workflows expressed as ordinary R control flow ("graph
  engineering": the R script is the graph).

### Interaction and safety
- **REQ-36** Ask-user capability: the agent can ask the user questions.
- **REQ-37** Permission modes: fully autonomous mode, manual (approve each
  action) mode, and intermediate modes.
- **REQ-38** Interrupt / abort / steer a running agent from the console.

### Artifacts
- **REQ-39** Artifacts are built with **Shiny** (interactive, compact to
  generate); HTML embedded in Shiny is the fallback. Static visualisations via
  ggplot2 etc.

## Known facts about the development machine
Historical design-session snapshot; see `dev/LOCAL_SETUP.md` for the current inventory.
- R 4.4.3 at `/usr/local/bin/R`. The repo's `.Rprofile` sources a non-existent
  `renv/activate.R`; use `Rscript --vanilla` when testing.
- Installed and useful: httr2 1.2.2, curl 7.0.0, jsonlite 2.0.0, processx 3.8.6,
  callr 3.7.6, later, promises, coro, cli, rlang, R6, S7, shiny 1.13.0, bslib,
  data.table, arrow, vroom, stringi, fs, withr, evaluate, knitr, rmarkdown,
  testthat 3.3.2, ellmer 0.4.0, future, yaml, digest, diffobj, roxygen2,
  devtools, rcmdcheck, httpuv, rstudioapi, openssl, base64enc.
- Not installed: mirai, nanonext, duckdb, collapse, qs2, httptest2, vcr,
  webfakes, mcptools, btw, quarto (R pkg and CLI), jupyter.
- CLIs present: `claude`, `codex`, `node`, `npm`, `gh`.
- The Jev key file is at `.secrets/jev-key.env` relative to the repository root (one variable,
  `jev-key`). Read it only through the package's `.env` loader during live
  System One tests; never print it.
- Pi source (read-only reference) is <https://github.com/earendil-works/pi>,
  researched at commit `1b347794` (2026-09-29). The design session's clone was
  temporary; recreate it with
  `git clone https://github.com/earendil-works/pi && git -C pi checkout 1b347794`
  when a report's `file:line` citation needs checking.

## Interpretive notes (transcription ambiguities resolved)
- "sorting algorithms and capabilities" → file discovery/listing with sorting
  (REQ-08), plus result ranking in search tools.
- "scale-agnostic MC-based plugins" → harness-agnostic MCP-based plugins
  (REQ-30).
- "P factors" → Pi's feature set (providers, skills, extensions, prompt
  templates, packages, sessions).
- "Quora Markdown" → Quarto Markdown (`.qmd`).
- "go-for-a-Kray library" → a ready-for-CRAN library.
- "Seret object" → Seurat object. "GEF"/"JEV" → Jev.

# gptr 1.0.0

gptr 1.0.0 is a complete rewrite. gptr is now an agent harness that runs inside the live R
session: `peter()` is an interactive chat at the console and a programmable function in
scripts, loops and `if` statements, and the agent works on the objects already in memory.

## Breaking changes

* The whole interface of gptr 0.7.0 is removed: its only two exported functions,
  `get_response()` and `dataframe_to_text()`, are gone, and no 0.x name is kept as a shim or an
  alias. Code written for 0.7.0 is rewritten as follows.
* `get_response()` has been removed. Use
  `s = peter("your prompt", model = "openai/gpt-6-sol")`, which returns a session object; its
  answer is `s$text`, and `s |> peter("next prompt")` continues the conversation. The key comes
  from `OPENAI_API_KEY` (or a `.env` file read with `gptr_env()`) instead of the `api_key`
  argument, instructions that went into `system_specification` go into the prompt or the
  project instructions file `.gptr/vignette.Rmd`, and answers stream to the console when a
  person is present instead of through `print_response`.
* `dataframe_to_text()` has been removed. Pass the data frame to
  `peter()` as context, for example `peter("Which variables are correlated?", mtcars)`: gptr
  describes the object compactly and the model computes on it in your session.
* Providers and models are chosen with the `model` argument or with `gptr_config()`.
* 'RCurl' is no longer used; HTTP is handled by 'curl'.
* R 4.2.0 or later is required.

## New features

* The interactive `peter()` console offers first-use setup when no default model is
  configured: choose Codex CLI or Claude Code CLI and save the choice at user scope, or get
  API configuration instructions. Explicit models, existing sessions and piped input skip it.
  Setup also shows CLI-reported login status (`signed in`, `not signed in`, or `unknown`)
  without a model request; `gptr_providers(check_login = TRUE)` exposes the same check.
  Same-name provider overrides must use the expected CLI adapter to be selected as CLI defaults.
* `peter()` is the single entry point. Without a prompt it opens a chat in the console; with a
  prompt it runs the agent loop and returns the session. The pipe steers one session:
  `peter("...") |> peter("...")` adds turns to the same object. `gptr_fork()` is the only way to
  branch. Sessions are saved in the project and resumed with `gptr_sessions()`,
  `gptr_resume()` and `gptr_last()`.
* The agent evaluates R code in the environment you pass (by default the caller's frame), so
  objects it creates stay in your workspace. It reads, writes and edits files, and searches
  them with `peter$grep()`, `peter$find()` and `peter$ls()`; shell, Python, SQL and knitr engines
  are reached through `peter$sh()`, `peter$py()`, `peter$sql()` and `peter$knit()`.
* Providers are implemented in R: Anthropic, OpenAI, Google Gemini, OpenAI-compatible
  endpoints and local Ollama servers, with streaming, tool calls, images, reasoning controls,
  prompt caching and cost accounting where the model supports them. The Claude plan (through
  the `claude` command-line tool, experimental) and the ChatGPT plan (through `codex`) are
  supported without keys. See `gptr_providers()` and `gptr_models()`.
* System 1 decisions: with a typed decision model, TypeSafe AI's Jev or Clef and Clef Flash on a
  local Ollama server (0.35.1 or later), `peter()` returns logical, choice or score vectors with
  their probabilities (`gptr_prob()`) that work inside `if`, `for` and `while`, one element per
  input. A generative model can emulate them; emulated answers are marked as uncalibrated.
* Permission modes `manual` (default), `edits`, `auto` and `plan`, rules with
  `gptr_permissions()`, and an advisory risk classifier, `gptr_risk()`. A permission question
  without a person present stops the run with a classed condition.
* Scripts and notebooks are the history: code the agent ran is recorded below each `peter()`
  call in `.R`, `.Rmd`, `.qmd` and `.ipynb` documents and replays without model calls
  (`gptr_doc()`, `gptr_source()`, `gptr_blocks()`, `gptr_cache()`).
* `gptr_init()` creates a `.gptr/` project workspace with the project instructions file
  `.gptr/vignette.Rmd`; `gptr_config()` and `gptr_trust()` manage settings and trust.
* Checkpoints: `gptr_rewind()`, `gptr_checkpoints()` and `/undo` restore objects, files and the
  conversation.
* Sub-agents, teams and fan-outs (`agents =`, `parallel =`, `gptr_parallel()`), across
  providers.
* Skills, prompt templates, agent files, extensions and plugins in R packages, all on one
  versioned extension API (`gptr_register()`, `gptr_spec()` and the spec constructors).
* MCP: a client for both protocol eras (`gptr_mcp()`, `gptr_mcp_add()`) that exposes server
  tools as R functions, and `gptr_mcp_serve()`, which serves the live session to other agents.
* Artifacts are Shiny apps launched in the background from the live session
  (`gptr_artifacts()`).
* Secrets are kept in a private vault and redacted everywhere; `gptr_login()` signs in to
  providers and MCP servers, `gptr_env()` loads `.env` files (including the `jev-key` alias) and
  `gptr_scrub()` cleans files that captured a key.
* Token accounting and budgets: `gptr_usage()`, `gptr_prompt()`, `gptr_describe()` and the
  `budget` argument.
* Background sessions (`background = TRUE`) are experimental.
* See `?gptr_security` and `?gptr_egress` for what gptr does on your behalf and what it sends to
  model providers, and `?gptr_options` for every option.

## Fixes

* `.opts = list(record = FALSE)` suppresses console recording questions and recorded
  System 1/System 2 blocks, including in explicitly bound documents. `TRUE` retains the
  existing recording consent checks.

# gptr 0.7.0

* Last release of the 0.x interface, `get_response()` and `dataframe_to_text()` for the
  OpenAI 'ChatGPT' API (released 2025-04-05, after 0.5.0 and 0.6.0 in May 2024).

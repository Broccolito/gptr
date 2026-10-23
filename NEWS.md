# gptr 1.0.0

gptr 1.0.0 is a complete rewrite: an agent harness that runs inside the live R session and
works on the objects already in memory.

## Breaking changes

* The 0.7.0 interface, `get_response()` and `dataframe_to_text()`, is removed with no aliases.
* Instead of `get_response()`, use
  `session = peter("your prompt", model = "openai/gpt-6-sol")`, which returns a session object;
  its answer is `session$text`, and `session |> peter("next prompt")` continues the conversation.
  The key comes from `OPENAI_API_KEY` (or a `.env` file read with `gptr_env()`) instead of the
  `api_key` argument, instructions that went into `system_specification` go into the prompt or
  the project instructions file `.gptr/vignette.Rmd`, and answers stream to the console when a
  person is present instead of through `print_response`.
* Instead of `dataframe_to_text()`, pass the data frame to `peter()` as context, for example
  `peter("Which variables are correlated?", mtcars)`: gptr describes the object compactly and
  the model computes on it in your session.
* Providers and models are chosen with the `model` argument or with `gptr_config()`.
* 'RCurl' is no longer used; HTTP is handled by 'curl'.
* R 4.2.0 or later is required.
* gptr is now licensed under the Apache License 2.0; gptr 0.7.0 was MIT-licensed. Third-party
  notices are in `inst/COPYRIGHTS`.

## New features

* `peter()` is the single entry point. Without a prompt it opens a chat in the console; with a
  prompt it runs the agent loop and returns the session. The pipe steers one session:
  `peter("...") |> peter("...")` adds turns to the same object. `gptr_fork()` is the only way to
  branch. Sessions are saved in the project and resumed with `gptr_sessions()`,
  `gptr_resume()` and `gptr_last()`.
* With no default model, the interactive console offers Claude Code CLI or Codex CLI setup, or
  API instructions; `gptr_providers(check_login = TRUE)` shows CLI sign-in status.
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
* Successful removal of CLI billing variables emits an informational
  `gptr_message_billing_env` condition with the removed names, never their values. Handlers
  use `muffleMessage`; the notice respects `gptr.quiet`. Actual billing refusals remain errors.
* The `yolo` mode (`mode = "yolo"`, `/mode yolo`) runs actions without approval, including
  package installs, writes anywhere and gptr's own configuration functions. A person is still
  asked before deleting files outside the project or protected files, `rm(list = ls())`,
  quitting R, `options(gptr.*)` and sending a secret over the network; a one-time notice says
  so. The classifier reads code; it is not a sandbox.
* In a terminal, lines typed while the agent works steer it at its next step (setting
  `type_ahead`: `"steer"` or `"follow_up"`); `/command` and `!code` lines wait for the next
  prompt. The terminal does not echo them into the answer; each shows once in its notice. On
  the CLI routes a steer is sent after the CLI's current response.
* A block pasted at the `peter>` prompt of a macOS terminal is sent as one message, and a line
  typed or pasted before a question (an approval, a choice or a yes/no confirmation) never
  answers it. A block pasted at an approval or a choice is dropped, not read as the answer, and
  pasted fences and `"""` blocks are read at once.
* R in the Terminal tab of RStudio or Positron is treated as a terminal (completion, pause menu,
  interrupt key), and `!code` completes R code at `peter>` there and in RStudio's console.
* The console keeps answers, tool calls, notices and prompts in a two-column margin with one
  blank line between them, aligns Markdown tables, keeps nested lists and highlights code. Code
  blocks and multi-line tool code are shown as Markdown fences that copy and run as written.
* A sub-agent's approval prompt reaches the console even while the parent's R code runs and
  names the sub-agent; an invalid answer is explained. Fan-outs, teams and `gptr_parallel()`
  print one line when each sub-agent starts and ends.
* A `peter()` call made by the agent's own code without `envir =` works in an overlay of the
  caller's environment; its objects are in `res$envir`.
* Object sizes are honest: S7 objects such as ggplot2 plots are not sized by `object.size()`,
  code the agent runs keeps no parse data, and values returned by sub-agents stay small.
* Codex reaches the session through a base-R stdio relay, without 'httpuv', 'later' or
  'openssl', and both CLI routes get the session's full tool set. Codex reasoning and commands
  show as progress lines and Claude Code's calls of gptr's tools as tool lines while they run.
* `/model` and `model =` accept a provider name alone, such as `claude-cli` or `codex-cli`
  (its first model); `/model` checks the name before the first prompt. A model declared without
  tool calls says once that the session's tools are not sent.
* Amazon Bedrock's Converse API with AWS access keys: `api = "bedrock-converse"` signs requests
  with Signature Version 4 in R. Region and endpoint are provider-record data
  (`compat = list(region = ...)`, `base_url`), so a SigV4 gateway is configuration; see
  `?gptr_provider`. `AWS_ACCESS_KEY_ID` is handled as a secret.
* On the Claude Code and Codex CLI routes, cost and tokens count each turn's increase of the
  CLI's running totals instead of the totals themselves. The status line counts the run's
  requests and adds what its sub-agents cost, `/cost` lists each agent and one total that keeps
  the known cost when a request's cost is unknown, and `/context` says the CLI keeps its own
  transcript.
* On the CLI routes, `/undo` and `gptr_rewind()` restore what the agent's served calls changed,
  and a rewind or compaction starts a fresh CLI conversation. Automatic compaction does not run
  there, since the CLI keeps its own context. `/undo` reports each item once, by its outcome.
* Multi-panel plots such as `par(mfrow = c(1, 2))` keep every panel and knitr chunks keep their
  figures; plots of calls served to the CLI routes are drawn on your device.
* A fan-out child gets its own element as `.x`; `parallel =` with `.opts$context = "none"` is an
  error. A `peter()` call made by the agent's code without `model =` uses the running session's
  model, and the egress question names the sub-agent that asks. Assignments in a sub-agent's
  overlay are not reported as overwriting your objects.
* The delete guard also covers a path held in a variable assigned from literals, as in
  `p = normalizePath("../x.txt"); file.remove(p)`.
* Console layout: the approval prompt lists at most five flagged calls, one per line, and offers
  `[a]` only when it has a rule to suggest; result lines and errors wrap in the margin, and a
  failed `r` call still lists its objects; sub-agent failures give their reason and count, and
  repeated nested prompts are numbered; command output and long prompts stay in the margin;
  Codex commands show without their shell wrapper and Codex messages without a held last word; a
  cut code block says so inside its fence; wide pipe tables stream verbatim; `/model` and
  `/status` name the model behind a CLI's `default`.
* `gptr_models(refresh = TRUE)` reads each models.dev price tier once, so models with a
  200k-token price tier resolve and a 272k tier no longer gains a premium from 200k tokens. A
  catalog refreshed by an earlier build is set aside until the next refresh downloads it again.
* A model alias with no model in the catalog is an unknown model, not a guess: offline,
  `model = "gemini"` (Google's newest Gemini Pro) no longer runs Gemini Flash and asks for
  `gptr_models(refresh = TRUE)` or a `provider/id`.
* Models whose catalog gives the whole context window as their output limit (common after
  `gptr_models(refresh = TRUE)`, for example MiniMax-M3 and gpt-oss-120b) are no longer refused
  as too small: gptr reserves and requests at most half the window for output. A `compact_at`
  too small for the preset is named as the cause instead of the model, and the hint reads
  `tools = "minimal"`.

# gptr 0.7.0

* Last release of the 0.x interface, `get_response()` and `dataframe_to_text()` for the
  OpenAI 'ChatGPT' API (released 2025-04-05, after 0.5.0 and 0.6.0 in May 2024).

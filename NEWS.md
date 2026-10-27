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
  branch. Sessions are saved in the project's `.gptr/` workspace (without one, until R exits)
  and resumed with `gptr_sessions()`, `gptr_resume()` and `gptr_last()`.
* With no default model, the interactive console offers Claude Code CLI or Codex CLI setup, or
  API instructions; `gptr_providers(check_login = TRUE)` shows CLI sign-in status.
* The agent evaluates R code in the environment you pass (by default the caller's frame), so
  objects it creates stay in your workspace. It reads, writes and edits files, and searches
  them with `peter$grep()`, `peter$find()` and `peter$ls()`; shell, Python, SQL and knitr engines
  are reached through `peter$sh()`, `peter$py()`, `peter$sql()` and `peter$knit()`.
* Providers are implemented in R: Anthropic, OpenAI, Google Gemini, OpenAI-compatible
  endpoints and local Ollama servers, with streaming, tool calls, images, reasoning controls,
  prompt caching (not yet through `api = "bedrock-converse"`) and cost accounting where the
  model supports them. The Claude plan (through the `claude` command-line tool, experimental)
  and the ChatGPT plan (through `codex`) are supported without keys. See `gptr_providers()`
  and `gptr_models()`.
* System 1 decisions: with a typed decision model, TypeSafe AI's Jev or Clef and Clef Flash on a
  local Ollama server (0.35.1 or later), `peter()` returns logical, choice or score vectors with
  their probabilities (`gptr_prob()`) that work inside `if`, `for` and `while`, one element per
  input. A generative model can emulate them; emulated answers are marked as uncalibrated.
* Permission modes `manual` (default), `edits`, `auto` and `plan`, rules with
  `gptr_permissions()`, and an advisory risk classifier, `gptr_risk()`. Deny and ask rules also
  match read-only shell commands, such as `r(sh:cat *)`. A permission question without a person
  present stops the run with a classed condition. In `auto` and `yolo` mode, `system()`,
  `system2()`, `shell()` and `shell.exec()` with a command the code computes (`system2()`'s `env`
  included) are refused unless an allow rule such as `r(fn:system)` names the function; the model
  is pointed to `peter$sh()`, whose command the rules check when it runs.
* Scripts and notebooks are the history: code the agent ran is recorded below each `peter()`
  call in `.R`, `.Rmd`, `.qmd` and `.ipynb` documents, also what a call ran before it failed,
  and replays without model calls (`gptr_doc()`, `gptr_source()`, `gptr_blocks()`,
  `gptr_cache()`); `gptr_source(model =)` asks a recorded analysis again with another model. A
  console transcript also records a run that was aborted or stopped by an error, marked
  `## Run: <status>`.
* A console transcript records what each prompt was sent with (the head of each `@file` and the
  notes of earlier `!` lines, as `#< ` lines) and, after `/model` or `/mode`, the model and mode
  a turn ran with, so `gptr_source(replay = "live")` sends each turn again with what it was sent
  with and asks it on that model and in that mode (a turn that names none is asked with the
  `model` and `mode` settings of the session that re-asks); code the model wrote is never sent
  again as your context or your steer. A `!` line that uses an object of an undone turn is turned
  off (`#~ `) and back on after `/redo`, so `source()` does not stop there, and `/retry` sends the
  undone turn's `!` notes again. `gptr_export()` turns such a transcript into an ordinary R
  script.
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
  `options(gptr.*)` and sending a secret over the network; a one-time notice says so. The
  classifier reads code; it is not a sandbox. In every mode, model code that would end or hang
  the R session, such as `q()` or `readline()`, is refused without a question.
* In a terminal, what you type while the agent works is a draft on the bottom row: Enter sends
  it as a steer, which the agent reads at its next step, and Tab as a follow-up, the next prompt
  (setting `type_ahead` swaps the two); Up takes back a message not yet delivered, and
  `/command` and `!code` lines wait for the next prompt. A paste is one draft, however busy the
  session, in a terminal that supports bracketed paste. A question waits for typing to pause and
  keeps the draft. On the CLI routes a steer is sent after the CLI's answer. In RStudio and R.app
  (Esc) and Positron (Ctrl-C) the pause menu steers.
* A line typed or pasted before a question (an approval, a choice or a yes/no confirmation)
  never answers it. In a macOS terminal (CRAN's R) a block pasted at the `peter>` prompt is sent
  as one message, pasted fences and `"""` blocks are read at once, a block pasted at an approval
  or a choice is kept in the console history, not read as the answer, and one pasted at the
  pause menu's steer or follow-up question is the whole message; a last pasted line without a
  newline waits for Enter at the next prompt, so a two-line paste without a final newline answers
  a question with its first line. Elsewhere a block pasted at a prompt or a question arrives one
  line at a time, as typed lines do.
* R in the Terminal tab of RStudio or Positron is treated as a terminal (completion, pause menu,
  interrupt key). Tab completes only after `@`, `!`, `!!`, `/` and `peter$`, never in plain
  text.
* The console keeps answers, tool calls, notices and prompts in a two-column margin with one
  blank line between them, aligns Markdown tables, keeps nested lists and highlights R code.
  Code blocks in answers are shown as Markdown fences that copy and run as written.
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
  Codex's own shell runs within Codex's sandbox, outside gptr's permission gate.
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
  `a` and `p` only when it has a rule to suggest; result lines and errors wrap in the margin, and a
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
* An Ollama model refused for missing or outdated discovery names
  `gptr_models(provider = "ollama", refresh = TRUE)` as the remedy, not the internal
  `model_prepare()`.
* `peter(model = "ollama/<model>")` asks the Ollama server about that model before its first
  request in each R session, as System 1 calls already did, instead of refusing until
  `gptr_models(provider = "ollama", refresh = TRUE)` had run. A saved default Ollama model now
  works in a new session.
* An unknown `provider/id` on a route the catalog lists no models for yet (before a refresh,
  for example OpenRouter, Groq, xAI or Azure) says that `gptr_models(refresh = TRUE)` downloads
  them from models.dev.
* `gptr_provider()` and `gptr_spec("model")` accept a model's `prices` as a list of price records
  as well as a data frame, as `gptr_config(providers =)` does, and check the table when the spec
  is built, naming the field, instead of failing at the first call.
* A provider without a valid base URL, such as `azure/` before `AZURE_OPENAI_ENDPOINT` is set, names
  the variable that sets it (or `providers$<id>$base_url` in `gptr_config()`).
* An unnamed list in a higher settings layer, such as a provider's `models` set with
  `gptr_config(.scope = "session")` or `options(gptr.providers =)`, replaces the one in a lower
  layer (for example the user file) instead of being ignored; named lists still merge.
* `gptr_config()` warns when it saves a setting to a project that is not trusted and so does not
  apply it (for example `providers` or `model`), naming `gptr_trust()` and `.scope = "session"`;
  settings that only tighten, such as `mode = plan` or `deny` rules, stay silent (a `permissions`
  write names only its `allow` rules).
* `gptr_config(model = opuss)` (or `small_model`, `system1`) warns when the name is not a model
  gptr knows in this session, as the console's `/model` already checked, with the reason and how
  to undo it; the value is still saved, since a provider registered later or a catalog refresh
  can make it valid.
* `gptr_init()` no longer writes `"mode": "manual"` and `"record": "ask"` into
  `.gptr/settings.json`, which overrode a user-level `mode = auto` or `record = "auto"` in every
  initialized project. In a project made by an earlier build, delete those two keys from the file
  to let your user settings apply.
* A trusted project's `mode` applies, so `gptr_config(mode = auto)` in a trusted project no longer
  saves a value that is silently ignored; an untrusted project still only tightens the mode, and
  `context` and `record` still only tighten in any project. A project cannot select `yolo`:
  `gptr_config(mode = yolo)` at project scope is refused, naming `.scope = "user"` and `"session"`.
* Providers declared with `api = "bedrock-converse"` send thinking levels
  (`.opts = list(thinking =)` or a `:high` suffix) to a Claude model whose record declares
  `capabilities = list(adaptive_thinking = TRUE, effort = TRUE)` (Claude 4.6 and later; see
  `?gptr_provider`); formerly every level was dropped without a word. Any other model, an
  undeclared Claude record included, still runs without thinking and now says so once.
* A string that is not one of an argument's choices, such as `.opts = list(thinking = "ultra")`,
  is reported as such ("the string given is not one of them", with "Did you mean" when it differs
  from a choice only in case) instead of "not a character of length 1".
* A thinking level the model does not offer still becomes the nearest one it has, and gptr now
  says so once per model and level: for example `"opus:off"` runs at `low`, and `thinking = "max"`
  on a model whose levels end at `high` runs at `high`. `?gptr_provider` documents
  `thinking_levels`; a reasoning model declared without it gets `off` to `high`.
* A known name, such as a model alias or a built-in tool, still wins over a variable of the same
  name, and gptr now says so when the variable holds a spec the argument takes (a provider or
  router for `model`, a tool for `tools`), as it did for a character value: after
  `opus = gptr_fake_provider(...)`, `model = opus` uses the alias and suggests `!!opus`.
* `choices`, `levels`, `threshold`, `min_confidence` and `uncertain` given to a conversational
  model, also with `agents =` or `parallel =`, are refused, naming the argument; they were ignored,
  and the call returned a session on which `sum()`, `[` and `gptr_prob()` then failed. Use a
  decision model such as `jev`; after `gptr_config(system1 = "emulate:<ref>")`, `model = jev` runs
  it through a chat model. A decision model, which ignored `agents =` and `parallel =`, refuses
  them: it answers every input in one call.
* The `uncertain = "stop"` error names the uncertain inputs (the first ten) and carries their
  positions (`$index`), `$names` and `$confidence`, the confidence the band tests, and every answer
  (`$value`), which it used to discard; `$prob` is unchanged.
* `as.data.frame()` of a System 1 score names its probability columns by level (`p_<level>`), as
  `gptr_prob(x, "probabilities")` and choices do; they were `p_0`, `p_1`, ...
* `choices` given as a factor, or `.opts = list(output = "factor")`, return a plain factor without
  probabilities, as `?peter`, `?gptr_prob` and the System 1 vignette now say. When elements fail,
  the factor keeps `attr(x, "meta")$errors`, which the failure warning points to.

# gptr 0.7.0

* Last release of the 0.x interface, `get_response()` and `dataframe_to_text()` for the
  OpenAI 'ChatGPT' API (released 2025-04-05, after 0.5.0 and 0.6.0 in May 2024).

# P26 Console and agent fixes (2026-10-16)

**Goal:** Fix the ten defects a maintainer found while using `peter()` interactively: pasted
blocks, steering by typing, `!code` completion, the console layout and code blocks, bare
sub-agent approval prompts and fan-out progress, misleading object sizes, a `yolo` mode, the
CLI routes' tools and their streaming. Issues
[#10](https://github.com/Broccolito/gptr/issues/10)-[#19](https://github.com/Broccolito/gptr/issues/19).

**Evidence:** every defect was reproduced in a real pty (CRAN macOS R 4.6.1, GNU readline 5.2)
or with the fake provider and checked by an independent skeptic before this plan was written.
The decisions below record the skeptics' corrections; a task's reviewer holds the implementation
to them.

**Depends on:** P01-P25 (all merged). **Milestone:** post-M5 maintenance, before CRAN submission.

## Global Constraints

`dev/plan/00-conventions.md` applies in full (house style, sections 5-8, section 11 simplicity:
the smallest design that meets the acceptance; no new Imports or Suggests; pure R; offline
tests; never `.GlobalEnv` by name; restore every option). Plan-specific rules:

- Authority: 04 (section 15 first, then the new section 15.9 written by these tasks) > 03 > this
  plan. Each task amends the spec sections it names in the same commit.
- Pre-assigned ids: each task owns one deviation entry (D-183..D-192, placeholders in
  `dev/DEVIATIONS.md`), one progress section (`dev/progress/P26.md`) and, where named, one
  contract item in 04 section 15.9 (IC-75..IC-79, placeholders). Edit only your own placeholder.
  `NEWS.md` is written once at integration from the progress log.
- Interactive behaviour is tested with mocks and, where named, a `skip_on_cran()` pty child.
  A test run from an interactive terminal must not read the developer's real fd 0: the console
  test helpers mock the fd-0 reader.
- Lanes (separate worktrees and branches, merged at integration): A = Tasks 1-3 (console input),
  B = Tasks 4-6 (rendering, prompts, fan-out), C = Tasks 7-10 (objects, permissions, CLI routes).
  Shared files are edited in different functions only; a task never reformats code it does not
  change.

## File Structure

| Path | Tasks |
|---|---|
| `R/utils-options.R` | 1 (`front_end()`, `stdin_tty()`), 2 (`readline_answer()`), 6 (long prompts) |
| `R/console-repl.R` | 1 (completion gate, REPL readline), 2 (paste joining, fenced input), 3 (typed lines) |
| `R/console-interrupt.R` | 2 (`console_ask`), 3 (`policy_enqueue(source =)`), 4 (launch boundary) |
| `R/gptr-config.R` | 3 (`type_ahead` setting), 8 (mode docs) |
| `R/console-render.R` | 4 (layout, Markdown, highlighting), 5 (fences, tool lines), 6 (`console.status`) |
| `R/console-ui.R` | 2 (stale answers), 4 (prompts clear the waiting row), 5 (`?` detail), 6 (who asks) |
| `R/utils-conditions.R`, `R/eval-core.R` | 6 (console writer), 7 (`keep.parse.data`) |
| `R/subagent-*.R`, `R/gptr-gateway.R`, `R/tool-r.R`, `R/agent-dispatch.R` | 6, 7, 8 |
| `R/env-snapshot.R`, `R/env-describe.R`, `R/perm-classify.R` | 7, 8 |
| `R/perm-gate.R`, `R/session-object.R`, `R/tool-namespace.R`, `R/console-commands.R` | 8, 9 |
| `R/cli-codex.R`, `R/cli-claude.R`, `R/cli-common.R`, `R/mcp-server.R`, `R/http-reactor.R`, `R/catalog-models.R`, `R/provider-*.R`, `inst/gptr/mcp_relay.R` | 9, 10 |
| `tests/testthat/test-*.R` mirroring each file | every task |
| `dev/spec/03-architecture.md`, `dev/spec/04-interface-contract.md`, `?peter`, vignettes | every task, its own sections |

## Tasks

### Task 1: IDE terminal tabs are terminals; `!code` completion everywhere (#10, D-183)

Problem: completion of `!code`, the pause menu and the interrupt-key label are wrong in R started
from RStudio's or Positron's Terminal tab, and RStudio's console offers no completion at
`peter> `.

Decisions:
- `front_end()`: an interactive process whose stdin is a tty and whose IDE match comes only from
  inherited `RSTUDIO=1`/`POSITRON=1` is `"terminal"` (`"vscode"` with `TERM_PROGRAM=vscode`).
  `.Platform$GUI` checks are unchanged. Add a mockable `stdin_tty()` (one line,
  `isatty(stdin())`) used here and by Tasks 2-3.
- `repl_main()`: delete the `front_end()` term of the completion gate (`R/console-repl.R:612`);
  keep the scoped `rl_word_breaks` restore and the custom-completer exclusion.
- RStudio console: the REPL's line reader calls a copy of `base::readline` that carries one
  attribute (same formals, body and environment, not `identical()`), because RStudio's
  `.rs.readlineCompletions` suppresses completion only for frames identical to
  `base::readline`. Approval and menu prompts keep `gptr_readline()` (RStudio's choice
  completion stays there). No `.Internal` in gptr code.
- Document per front end in `?peter` (terminal R and IDE terminal tabs: full completion;
  RStudio console: R completion via the reader; radian and Positron's console: none).

Tests (`test-console-completion.R`, `test-utils-options.R`), RED first: an IDE terminal tab with
cledit and a tty gets `" ,;!"` and restores `" ,;"`; the old front-end exclusion test is rewritten
to model an IDE console as `tty = FALSE`; `front_end()` with `RSTUDIO=1` + tty is `"terminal"`,
without tty `"rstudio"`; the reader's readline is not `identical()` to `base::readline` but has
its formals and body. Spec: 03 section 6.17 (REPL completion bullet), 03 section 6.2 (IDE
terminal tabs have the pause menu). Commit: `fix(console): treat IDE terminal tabs as terminals and complete !code everywhere`.

### Task 2: A pasted block is one message; stale input never answers a question (#11, D-184, IC-75)

Decisions (skeptic-corrected):
- Paste joining, macOS terminal only (`is_macos() && stdin_tty()` and the Task 1 gate): after
  `repl_read_logical()` reads a plain, slash or `!` line, `console_typed_lines(rd)` polls fd 0
  with `processx::conn_create_fd(0L, close = FALSE)` kept in `rd$fd` (created inside the
  `tryCatch`; dropped with the reader, NEVER `close()`d: closing it closes fd 0), up to 50 ms per
  poll, reading with `processx::conn_read_chars()` only (`conn_read_lines()` blocks forever on a
  chunk without newline) and splitting on `\r\n|\r|\n`. Waiting lines join the input; a dim
  `(pasted: Enter sends it as one message)` hint and one `... ` read follow, where Enter alone
  sends and typed text is appended. `"""` blocks and fences never poll. Long prompts (over
  200 bytes; R keeps 255) are printed whole and read after `> ` (moved here from Task 6). Piped `.stdin = TRUE`
  stays line-based. Linux and other front ends are documented ("use `\"\"\"`"); no inputrc tip.
- Stale answers, every front end: `gptr_readline()` records the duration of its `readline()` in
  `the$readline_secs` (timed with `proc.time()[["elapsed"]]`); `readline_answer(prompt)` re-reads
  while an interactive answer arrived in under 0.1 s, at most 100 reads, then returns the last.
  Used by `ui_console_read()`, the terminal branch of `console_ask()` and `gptr_confirm()`; the
  main prompt keeps `gptr_readline()`. Add `readline_secs` to the namespace-state list of 03
  section 2.2 rule 5.
- Fenced input (`repl_read_logical()`): a fence runs as the user's R only for an info string of
  `r`, `R`, `{r...}` or empty; other fences are message text; the body is de-indented by the
  opener's indentation and closes on a fence of at least the opener's length (CommonMark).

Tests (`test-console-repl.R`, `test-console-ui.R`, `test-utils-options.R`,
`test-console-completion.R` mock gains `waiting`), RED first: joined paste with blank and indented
lines; paste without final newline completed at `... `; `!x = 1` plus waiting `y = 2`; `"""` and
fences never poll; stdin reader never polls; readline-limit line drops the waiting lines; stale
`h$config$codex` and `y` skipped then `n` denies; `readline_answer()` bounded; acceptance: 3
pasted lines give 1 fake request; a `skip_on_cran()` macOS pty child: paste is one turn, Ctrl-D
after a partial typed line does not hang. Spec: 03 section 6.17 grammar bullet ("on a macOS
terminal ..."), 04 section 7.1 wrapper row, IC-75 (paste joining scope, stale-answer rule, the
fd-0 connection is not an R connection and is never closed; read with `conn_read_chars()` only).
Commit: `fix(console): join pasted blocks and never take typed-ahead lines as answers`.

### Task 3: Typing while the agent runs steers it (#12, D-185, IC-76)

Decisions (skeptic-corrected):
- Gate `repl_terminal(rs) = !isTRUE(rs$stdin) && !is_windows() && gptr_is_interactive() &&
  stdin_tty()` (no `front_end()` term).
- `console_send()` creates `reactor_task(console_typed)` (a package function, rule R3) for the
  call and cancels it on exit. `console_typed()` reads complete lines with Task 2's
  `console_typed_lines(rd)` (one fd-0 reader for both features) and returns the 0.1 s period.
- Lines matching `^\s*[/!]` are held in `rd$typed` and returned by the next `read()` (echoed with
  the prompt); one notice lists them. The remaining lines of a batch become ONE message queued on
  the running session through `policy_enqueue(target$session, text, as, source = "repl")` inside
  `console_render_pause()`/`console_render_resume()`; `policy_enqueue()`/`policy_flush()` gain
  `source` (default `"pause_menu"`). `as` is the new setting `type_ahead`
  (`rec("type_ahead", "steer", "choice", ..., choices = c("steer", "follow_up"))`).
- Notices show the text: `[gptr] steering: '<text>'; it reaches the agent at its next step` and
  `[gptr] follow-up queued: '<text>'; it is sent when the agent would stop`.
- An interrupted run clears `rd$typed` and lists the lines as dropped.
- The console test helper mocks `console_typed_lines` to `character()`.
- RStudio/Positron/R.app consoles: unchanged (R cannot read the console while busy); the pause
  menu stays the steering path there. CLI routes: a steer reaches the model after the CLI's
  current response. Both are documented in `?peter`, `/help` and the interactive-console
  vignette.

Tests (new `test-console-typing.R`, `test-gptr-config.R` key set), RED first: a typed line steers
the same run (operator relay, `s$turns == 1`); `type_ahead = "follow_up"`; a line typed during a
tool arrives after its result; `/status` and `!x = 1` run after the answer; a paste batch is one
message; no polling outside a tty REPL (`.stdin`, plain `peter()`, jsonl); an interrupt drops held
lines; a `skip_on_cran()` pty child proves the reader returns complete lines only, survives
Ctrl-D and a `/dev/null` stdin. Spec: 04 section 11.2 row, section 10.4 `input` row, IC-49
producers, IC-76; 03 sections 6.2 and 6.17; report 18 Verification log ("terminal R can read
complete typed lines during a run"). Commit: `feat(console): typed lines steer the running agent (type_ahead setting)`.

### Task 4: Console layout: margin, block spacing, waiting row, Markdown, highlighting (#13, D-186)

Decisions (skeptic-corrected):
- Margin: when the console renderer is active (`verbosity() >= 2L && cli::is_dynamic_tty()`)
  every line printed for a foreground run
  starts with two spaces: text, list items, quotes, tables, fences and code, tool lines, notices
  (`console_notice()` and gptr condition display word-wrapped inside the margin), approval
  prompts and the status line; content width `width - 4`. Rscript (verbosity 1), Jupyter, knitr
  and jsonl are byte-identical to today; `NO_COLOR` removes colours and styles only, so the layout
  stays; `capture.output()` of an interactive call captures the layout.
- Blocks: answer text, tool group (call and result lines), notice group, prompt, status line.
  Exactly one blank line between neighbouring blocks, one after the user's input line and one
  after the status line before the next prompt; a reply's leading and trailing blank lines are
  dropped and runs collapse to one (one pending-blank counter in the renderer).
- Waiting row: the spinner frame gets the margin; clearing uses `\r\033[K` when
  `cli::is_ansi_tty()`, spaces otherwise; a cleared row is never followed by an LF except on
  `rgui` (the launch-boundary `newline` argument goes away). Separators are written on finished
  lines, so the next block overwrites the cleared row. The spinner leaves the cursor at the end of
  its text (typing stays visible).
- One "other output is about to appear" path: `console_before_message(runs = NULL)` ends partial
  Markdown lines of every foreground record and clears waiting rows but keeps their tasks. It is
  the first statement of `ui_console_permission()`, `ui_console_select()` and
  `ui_console_input()`; `console_on_permission()` and its hook are deleted. After an approval the
  waiting row resumes by itself (CLI routes keep their request pending);
  `console_on_tool_end()` restarts the waiting row while `rec$request_pending`.
- Markdown: nested list indentation kept (`•`/`◦`, ASCII `-`), italic at token edges, dim link
  URLs (text and brackets kept), dim `> ` quotes, dim rules, headings (H1 bold underlined, others
  bold), aligned pipe tables buffered per block with a verbatim fallback (wrong cell counts, no
  delimiter row, too wide). Strikethrough and bare-URL underline are not added.
- Highlighting: complete R code through `cli::code_highlight()` with a `tryCatch` fallback; a
  15-line `code_light(line, lang)` (strings, numbers, end-of-line comments for `#`, `//`, `--`
  languages, cli's default theme colours) for other languages and for streamed R lines that do
  not parse alone. R fence detection accepts `r`, `R`, `{r...}` and `r <title>`.

Tests (`test-console-render.R`, `-ui`, `-process-launch`, `-spinner-width`, `-notice`, `-wait`),
RED first: margin and width at 40 columns; plain mode unchanged; block spacing incl. a reply ending
`\n\n`; no `\r +\r\n` in a terminal run; a prompt clears the waiting row, keeps the task and a
later tick redraws; nested lists, tables, italics, links, quotes, rules; R statement and python
highlighting; chunk invariance over 200 random splits in the four `cli.dynamic` x colour modes;
launch boundary without LF except rgui. Spec: 03 section 6.17 Rendering, P14 Task 1-2 notes.
Commit: `feat(console): margin, block spacing and richer Markdown in the console renderer`.

### Task 5: Code blocks and tool calls as Markdown (#14, D-187)

Decisions:
- `console_symbols()` loses `bar`, `top`, `bottom`, `result`: no box-drawing characters anywhere
  in console output (grep `R/` for U+2500-U+257F and U+23BF).
- Fences: the fence lines are printed as written (dim when styled), the body verbatim and
  unwrapped, de-indented by the opener's indentation (CommonMark: fences indented 4+ spaces under
  list items close), highlighted per Task 4. Code lines stream as their characters arrive; on the
  line end a line that fit one row is redrawn highlighted (`\r` + margin + line), otherwise left.
- Tool calls: `  ● r  <code>` when the escaped code fits the width on one line; otherwise
  `  ● r` and a fence of `doc_rmd_fence()` backticks (moved to `R/utils-text.R`, all callers
  updated) with up to 20 code lines, then a dim `(+N more lines)` line when cut. Result lines use
  a plain 4-space indent; an r error shows `error: <details$error>`; the duplicate tool line at a
  manual approval is not repeated by the prompt (the prompt's first line names the tool only).
- The `?` approval detail shows the code as a plain ```` ```r ```` fence (no SGR: it also feeds the
  RStudio dialog), at most 40 lines with the cap line outside the fence.

Tests (`test-console-fences.R`, `test-console-render.R`, `test-console-ui.R`), RED first: styled
UTF-8 output stripped of SGR equals the source Markdown for r, python and no language, contains no
frame character, and `parse()` succeeds on the body; a fence indented 4 and 8 spaces under a list
item closes and copies unindented; a long one-line call and a 2-line call render as fences, never
cut; nested backtick fences get a longer fence; `error: boom`; fence characters appear before the
line end. Spec: 03 section 6.17 Rendering (fence rule, no box drawing). Commit: `fix(console): render code blocks and tool code as Markdown fences`.

### Task 6: Prompts reach the person and say who asks; fan-out status; nested calls in overlays (#15, D-188, IC-77)

Decisions:
- Console controls are never captured: the evaluator's `.gptr_message_write` writer lifts its
  own capture sink (only when it is on top: user sinks are never popped), writes through the next
  writer below (nesting works) and restores the sink. `console_notice()` and the console UI
  (`ui_console_permission`, `_select`, `_input`, notify) write through `gptr_message_write()`
  instead of `msg_verbatim()`.
- The permission request record gains `agent` (`run$opts$agent %||% "main"`); the prompt's first
  line is `  sub-agent <name> > r  <code>` (`sub-agent > ` for `"nested"`), the detail view says
  `sub-agent <name> wants to use ...`, an `ask_human` prompt adds `asks in every mode: <reason>`,
  and `ask` questions from children start `sub-agent <name> asks: `.
- Invalid answers: `a`/`p` where nothing can be remembered explains why; other text says
  `Not an answer: '<text>'` with the allowed letters; after 5 invalid answers the console says
  so and the deny feedback is `no valid answer was given at the approval prompt`.
- Long prompts are Task 2's (it owns `gptr_readline()`).
- Fan-out progress (skeptic-corrected, no new service): the existing `agent_start`/`agent_end`
  console hooks print one line per child run (depth >= 1: nested `peter()` loops, fan-outs,
  teams, `gptr_parallel`, worker and cli proxies) whose root session is in the foreground, at
  verbosity >= 1 and not quiet: `  sub-agent <label> started (<model>)` and
  `  sub-agent <label> done (k/N) · <turns> turns · <secs> s` or `... failed: <status>`; `(k/N)`
  only for a scheduled group. Every console-renderer write goes through
  `gptr_message_write()`, and anything drawn mid-line first ends partial lines. Unnamed nested
  children are labelled by a 30-character preview of their first prompt.
- `r_tool_execute()` tees only for depth-0 runs: children's raw output no longer reaches the
  parent's tool result or the console.
- Nested calls: a `peter()` from model code (also `gptr_parallel()` members created in a run)
  without an explicit `envir =` evaluates in `overlay_new(call$envir, ...)`; results stay in
  `res$envir`; function-frame callers unchanged (R2). The `<r_session>` fragment says so.
  `subagent_overlay()` is replaced by `overlay_new()`.

Tests (`test-console-message-stream.R`, `test-console-ui.R`, `test-agent-dispatch.R`,
`test-subagent-team.R`, `test-cli-claude.R` with a fan-out fixture, `test-console-render.R`,
`test-utils-options.R`, `test-gptr-gateway.R`, `test-copy-gateway.R`, `test-tool-r.R`,
), RED first, including the end-to-end fan-out whose console shows
`sub-agent a > r  cm = 1; pp = 2` and the status line while the parent tool result contains none
of it. Spec: 04 sections 7.9, 7.11, 6.1 `envir` row, IC-77; 03 sections 5.8, 6.8.3, 6.13,
6.17, 7.3. Commit: `fix(console): sub-agent prompts reach the person and fan-outs show progress`.

### Task 7: Object sizes and agent-made object bloat (#16, D-189)

Decisions:
- One size rule: `env_snap_size()` returns NA for S7 objects as for environments and functions
  (`object.size()` counts each S7 class object in full); `dsc_leaf_core()` and
  `risk_binding_leaf()` reuse it. NA sizes sort with sized objects by name rather than last.
- `eval_parse()` sets `keep.parse.data = FALSE` around `parse()` (restored with `on.exit()`).
- Worker exports: `save_rds(..., refhook = function(x) if (identical(x, envir)) "home")` in the
  worker and `readRDS(st$result_path, refhook = function(x) st$home)` in the parent: the worker's
  private home comes back as the proxy overlay whose parent is the home.
- A finished one-shot fan-out child's non-exported overlay bindings are removed after
  `subagent_export()`; team members that persist keep theirs. `?peter` and the agent docs say
  exports must be self-contained.
- The prompt line "Check size first (dim(), object.size())" gains "(object.size() overstates S7
  objects such as ggplot2 plots)".

Tests (`test-env-snapshot.R`, `test-perm-classify.R`, `test-env-describe.R`, `test-eval-core.R`,
`test-subagent-worker.R`, `test-subagent-team.R`, `test-prompt-text.R`), RED first: a hand-made
S7-classed object shows no size and does not trip protect_size; parse data absent and option
restored for both `keep.parse.data` states; a worker-exported formula serializes under 10 KB, its
environment's parent is the base and an exported `f = function() length(d)` still works; a fan-out
child's export no longer keeps its scratch object; guard: objects made through `peter()` and
through `mcp_dispatch_local()` capture the session home. Spec: 04 env_snapshot, eval_r and
worker_main rows; 03 section 6.4 R4. Commit: `fix(env): honest object sizes and console-sized agent exports`.

### Task 8: The `yolo` permission mode (#17, D-190, IC-78)

Decisions (skeptic's design B plus one classifier cell):
- `session_modes = c("plan", "manual", "edits", "auto", "yolo")`; every literal mode list uses it
  (console-commands, subagent-backends, ext-check, ext-specs, gptr-capture, cli-common with an
  explicit `"yolo"` at L1). Nested calls and project settings only tighten.
- `perm_policy_mode`: `yolo` allows before the control check. `perm_policy_critical`: in yolo,
  control rows do not count except `options(gptr.*)`; any remaining level-4 row asks a person
  while `critical_guard` is on. `perm_policy_secret`: yolo returns NULL after the
  secret-to-network flow check. `perm_policy_protect`: skipped in auto and yolo.
- `perm_check` grants the one-shot control tokens on any final allow (the tier condition goes).
- Classifier: a delete keeps category `file_delete` (control targets show in `path_class`; four
  sites in `perm-classify.R`); `risk_op_level()` makes a delete of an `outside` path level 4 in
  every mode; the edit tool's `*** Delete File:` takes `risk_op_level(path_class, "delete")` when
  that is 4.
- Model text: `<mode name="yolo">` reuses auto's body. A one-time notice on entering yolo (session
  start, `/mode`, REPL start) lists what still asks and that the classifier is not a sandbox.
- CLI: Codex maps auto and yolo to `workspace-write`; claude unchanged. Children inherit yolo.

Tests (`test-perm-gate.R` yolo column and rows, `test-perm-classify.R`, `test-perm-plan.R`,
`test-tool-namespace.R`, `test-session-object.R`, `test-console-commands.R`,
`test-console-repl.R`, `test-subagent-backends.R`, `test-subagent-defs.R`, `test-cli-common.R`,
`test-cli-codex.R`, `test-ext-specs.R`, `test-ext-check.R`, `test-gptr-config.R`,
`test-injection-e2e.R`, `test-prompt-context.R`), RED first; e2e: a control export runs in yolo
with no prompt; `options(gptr.critical_guard = FALSE)` from model code asks; nested
`peter(mode = "auto")` cannot delete a protected fixture silently; `.env` via the edit tool asks.
Spec: 03 sections 6.8.1-6.8.2, 8.3; 04 mode lists, IC-53 items 1, 3, 6, IC-65 mapping, IC-78; 05
P11 note; plans P02, P11, P19, P20 snippets. Commit: `feat(perm): add the yolo mode`.

### Task 9: Every provider gets the session tools; Codex stdio relay; model references (#18, D-191, IC-79)

Decisions (skeptic-corrected):
- Codex always reaches gptr through `inst/gptr/mcp_relay.R` (base R): Codex starts
  `Rscript --vanilla <relay> <dir> <timeout>`; the relay passes each stdin line through the
  private 0700 mailbox directory (fixed names `req`/`resp` written via `.tmp` + `file.rename()`;
  the relay is sequential), exits at stdin EOF, when the directory disappears or after the
  timeout, and retries a locked read on Windows. Paths are TOML basic strings
  (`normalizePath(winslash = "/")`, `\` and `"` escaped). `pcli_codex_relay()` is a reactor task
  that answers through `pcli_mcp(msg, s, answer)`, factored out of `pcli_claude_mcp()` (FIFO,
  abort and turn-over refusals). `startup_timeout_sec=60`. Delete `pcli_codex_ensure/_forget/
  _mcp/_files_only/_env`, `mcp_serve_ensure` and its service, `reactor_served` and the served
  clause, `mcp_serve_busy`. `gptr_mcp_serve()` for external clients is unchanged.
- `mcp_dispatch_local()` serves and validates the session's frozen tool declarations
  (`session_data(s)$frozen$tools_json`, session-scoped lookups, `mcp_r_schema` for `r`), falling
  back to the four defaults only when nothing is frozen; served calls run `tool_call_hook()` while
  a run is live.
- One adapter helper replaces the three `tools_on = !isFALSE(model$tool_call)` sites; it emits
  one notice per model when non-empty tools are dropped, naming how to declare
  `tool_call = TRUE` (IC-74 unchanged).
- `model_match()`: after the exact-id and alias steps and before fuzzy matching, a registered
  provider named alone means its first declared model; alias names compare with
  `catalog_norm_id()`. `cmd_model()` validates before the first prompt (keeping the user's text).
  Add the alias `codex-cli` -> `codex`.

Tests (`test-cli-codex.R` rewritten argv and relay e2e without httpuv/later/openssl,
`test-mcp-server.R`, new relay unit tests, `test-catalog-models.R`, `test-console-commands.R`,
`test-provider-*`, `test-cli-common.R`, `test-http-reactor.R`, `test-live-cli.R` loses its three
skips; fixture `inst/gptr/fixtures/fake_cli.R` spawns the relay from argv), RED first. Spec: 03
sections 1.x line 140, 8.3 and the Suggests table; 04 sections 7.0, 8.5, 2888 row, IC-19, IC-58,
IC-65, IC-79; P19 and P20 plan text. Commit: `feat(cli): codex reaches the session through a stdio relay; CLI routes serve the session's tools`.

### Task 10: Streaming and visibility on the CLI routes (#19, D-192)

Decisions:
- Codex: `item.started`/`item.completed` of reasoning items render as dim progress lines at
  verbosity 2 (one line each, within the margin); command and MCP items render as tool lines (as
  today) and the waiting row resumes after each. Full text deltas need `codex app-server`
  (deferred, 03 section 1.3): recorded as an open item.
- claude-cli: MCP-served `mcp__gptr__*` calls emit informational `tool_execution_start`/`end`
  events so they render like native tool calls (tool line, result line), without changing the
  gate.
- The CLI probe (`pcli_probe()`) no longer freezes the waiting row on the first turn: it runs
  before the waiting row starts or through the reactor.

Tests (`test-cli-codex.R`, `test-cli-claude.R`, `test-console-render.R`), RED first: a fake codex
reasoning and command item render before the final message; a fake claude MCP r call renders a
tool line and its result; the first CLI turn's waiting row is drawn before the probe returns or
the probe runs before it. Spec: 03 section 8.3, P20 note. Commit: `fix(cli): show codex progress and claude-cli tool calls while they run`.

## Integration (coordinator)

1. Merge lanes A, B, C into the session branch; resolve shared-file hunks; renumber nothing (ids
   were pre-assigned).
2. `devtools::document()`, full `devtools::test()`, lint, cross-plan checks
   (`dev/research/assets/consolidation-tools/README.md`), `R CMD check --as-cran --no-manual`.
3. Live dogfood in terminal R (Seurat analysis, iterative steering, a fan-out, rebuilding `kdps`
   with sub-agents) on the claude-cli and codex routes; fix what it finds as Task 11+ in this plan.
4. NEWS.md from the progress log; PR to `main`.

## Plan acceptance

| Row | Command | Actual | Status |
|---|---|---|---|
| A1 | `isolated-check.R test 'console-'` | `[ FAIL 0 \| WARN 0 \| SKIP 1 \| PASS 1643 ]` (2026-10-17, after the merges) | pass |
| A2 | `isolated-check.R test 'perm-|session-object|subagent-|cli-|mcp-|catalog-|env-|eval-'` | `[ FAIL 0 \| WARN 0 \| SKIP 2 \| PASS 5841 ]` | pass |
| A3 | full `devtools::test()` | `[ FAIL 1 \| WARN 0 \| SKIP 51 \| PASS 33948 ]`: the one is the known auth-oauth `kill_tree` teardown race under load (helper-mcp-server.R:92); `test 'auth-oauth'` alone `[ FAIL 0 \| PASS 185 ]` | pass (load flake) |
| A4 | `isolated-check.R lint` (whole package) | `No lints found.` | pass |
| A5 | cross-plan checks | `26 plans, 1446 blocks, 4391 definitions, 28348 calls, 937 findings (info 823, warn 114)`, 0 error (base 18cd81e: 927, warn 104; the 10 new warns: 9 P26 helpers named in 04 sections 7.1, 7.9 and 15.9 that no plan block defines, and `gptr_readline(read =)` against P01's block); `770 R blocks; 0 with parse/style problems`; `no lints` | pass |
| A6 | `R CMD check --as-cran --no-manual` (0 errors, 0 warnings) | | |
| A7 | live terminal dogfood (Task 11+ list) | | |

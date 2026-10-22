# P28 Codex-style peter() console (2026-10-21)

**Goal:** Redesign the interactive `peter()` session using the Codex CLI (rust-v0.157.1) as the
template, within what R consoles support reliably:
- The person's input is never interrupted or consumed. This fixes the open bug: "the steering
  msg is still stacked onto the next window that pops up (sometimes it is the tool call ask, with
  yes no or always)".
- A message typed while the agent works is queued as one of two kinds, chosen per message:
  - a steer, which the harness injects into the agent's context at the first step boundary;
  - a follow-up, which is sent as the next prompt after the run ends.
- The input row stays at the bottom, with the transcript above it.
- Tool calls, approvals and notices follow Codex's style.
- The role glyphs come from the logo's cursor shapes and the colours from the logo palette. The
  input area is shaded. R code is highlighted.
- A minimal status shows the model, the context left and the mode.
- Completion works only after gptr's trigger characters.
- Only four small backend changes. History: issues #12, #28, #30 and #46; D-183..D-185, D-221;
  IC-75..IC-77.

**Evidence:** five research lanes, then two independent judges (scores 7 and 7); their changes
are taken below unless a decision says why not:
- Codex source at tag rust-v0.157.1, commit 36650394c5b3.
- Codex 0.157.1 driven live in a pty with a VT emulator (runs 1-7).
- R terminal tooling probed live on CRAN macOS R 4.6.1 (libedit "readline 5.2") in tmux, plus
  cli 3.6.6, RStudio 2026.09 and Ark sources.
- A gptr audit with a pty harness: scenarios A-I, a drain check, a history check and a composer
  prototype.
- This design.

Task 1 copies the facts this plan relies on into `dev/progress/P28.md`, because the research
scratch is not kept.

**Depends on:** P01-P27. **Milestone:** post-M5 maintenance, before CRAN submission.

## Steering, exactly (D-242; read before any task)

"Queued" does not mean "waits for the run to end". Two kinds of queued message exist. The person
chooses one for each message, and the `type_ahead` setting (`"steer"` or `"follow_up"`, default
`"steer"`, D-185) decides what Enter does:

| | Steer | Follow-up |
|---|---|---|
| Held | only until the first step boundary | until the whole run ends |
| Delivered | injected by the harness into the agent's context at the first step boundary after it was sent. The agent reads it on its very next request, as the operator relay `The user sent this message while you were working: <text>`. If the agent was about to stop, the loop makes one more request (after_turn polls steers) | sent as the next prompt after the run's status line, as its own run |
| Step boundary | the response in flight ends without a tool call, or the last tool call of that response returns | n/a |
| Terminal key (T class) | Enter when `type_ahead = "steer"` (the default), else Tab | the other key |
| Never | interrupts a request or a tool; waits for the run to end | joins the running run |
| Shown while queued | on the live row: `n queued`, and the newest message as `↳ steer · <text>` when the draft is empty; `↳ <kind> · <text>` lines in D and L consoles | the same, with `follow-up` as the kind word |
| Shown at delivery | `› <text>` on the band, at the boundary, before the next request's output | `peter> <text>` on the band, at the next prompt |
| Edit or withdraw | Up on an empty draft takes back the newest undelivered message (either kind) into the composer; Ctrl-U discards it | same |

The response's remaining calls are not skipped. A provider needs a result for every call of a
response, and both Codex 0.157.1 and Pi's current loop finish them. Skipping them would show the
agent failures it did not cause. In manual mode each remaining call is still asked, and
`n <text>` denies it with that text. Ctrl-C [a] stops everything.

Typing during an in-process `r` tool:
- Keys wait in the terminal buffer and are read when the tool returns.
- The console reads typed input at `turn_end`, before the loop polls steers (Task 7). So a
  message sent before a boundary reaches that boundary.

CLI routes (claude-cli, codex): the boundary is the end of the CLI's answer, which is often the
whole run. There a steer behaves like an in-run follow-up, and its queue line says
` · after the CLI's answer`. Mid-turn delivery through Claude Code's stream-json input or
Codex's app-server steer is a later plan.

RStudio, Positron and Windows consoles (L class) and TERM=dumb or ESS (D class) offer no
per-message choice:
- `type_ahead` decides.
- In L class, R reads nothing while busy. A line typed during a run steers only if a question
  reads it (Task 3). Otherwise it is the next prompt.

This replaces IC-76's "follow-up ... is sent when the agent would stop" and any text that treats
steering as end-of-run delivery.

## Global Constraints

`dev/plan/00-conventions.md` applies in full: section 11 simplicity, no new Imports or Suggests,
pure R, offline tests, `=` and `|>`, never `.GlobalEnv` by name, and every option, mode and
working directory restored. Plan-specific rules:

- Authority: 04 §15 first, then the new §15.10 that these tasks write, then 03, then this plan.
  Each task amends the spec sections it names in the same commit.
- Pre-assigned ids. origin/main already holds D-238..D-240, and D-241 belongs to the native-04 fix (#61).
  - Decisions:
    - D-242: steering semantics and the queue.
    - D-243: the composer, the live row and questions.
    - D-244: trigger-only completion and special tokens.
    - D-245: the output vocabulary (glyphs, palette, band, tool kinds, code, whole rows, status
      line).
  - Contract items: IC-81 (completion) and IC-82 (output vocabulary) in 04 §15.10, plus
    amendments to IC-75, IC-76 and IC-77.
  - Each task edits only its own parts of these.
- One task, one commit, one push:
  1. Write the red test and see it fail.
  2. Write the code; the test turns green.
  3. Run the task's filter and lint.
  4. In the same commit, record in `dev/progress/P28.md` the red output, the green output and any
     pty or live check.
  5. Commit with the task's message and push.
- Stable subset only (maintainer, 2026-10-21):
  - Whole lines are appended above one redrawn bottom row: `\r`, SGR, `ESC[K`.
  - No cursor addressing, save or restore, scroll regions or alternate screen.
  - No boxes, rules, box-drawing characters, Braille, dingbats or emoji.
  - Untrusted text goes through `cat()` after `console_escape()` (rule C1).
  - UI text goes to stdout.
- Front-end classes (decided by capability, not by name; one helper `console_class()`):

| Class | Test | Fronts |
|---|---|---|
| T | `repl_terminal(rs) && cli::is_ansi_tty() && cli::is_dynamic_tty()`, `RADIAN_VERSION` unset | terminal R on macOS/Linux, IDE terminal tabs, tmux |
| D | `repl_terminal(rs)`, not T | TERM=dumb, Emacs shell, ESS |
| L | interactive, not `repl_terminal()` | RStudio and Positron consoles (`repl_terminal()` excludes Positron, whose ark has a tty stdin; amended in the visual review), Windows Rterm/Rgui, R.app, radian |
| P | not interactive | Rscript, pipes, knitr, jsonl, `.stdin = TRUE` |

- Column rule: the person at column 0 (prompt, composer, delivered messages, answers), gptr at
  column 2. It holds wherever the margin applies (verbosity 2 on a dynamic tty). P keeps today's
  no-margin plain layout.
- Tests:
  - Pure functions with an injected clock hold the timing rules: 0.05 s poll, 0.1 s stale line,
    1 s typing idle, 50 ms escape hold, the batch rule.
  - pty children: `processx` pty, `skip_on_cran()`, `skip_on_os("windows")`, TERM=xterm-256color,
    80x24, temporary R_USER_* and GPTR_PROJECT_ROOT. One case per guarantee, run on the macOS and
    Linux NOT_CRAN lanes.
  - The console test helpers mock the fd-0 reader, so a test never reads the developer's fd 0.
  - New test files follow D-240's CRAN list rule. `test-console-input.R` (pure) joins the list in
    Task 16.

## File Structure

| Path | Tasks |
|---|---|
| `R/agent-run.R`, `R/agent-loop.R` (doc only) | 4, 5 |
| `R/session-object.R`, `R/ext-events.R` | 5 |
| `R/agent-dispatch.R` | 6 |
| `R/console-render.R` | 7, 8, 9, 10, 11, 12, 13, 15, 17, 18, 21, 26 |
| `R/auth-oauth.R` (input prompts) | 12 |
| `R/console-ui.R` | 2, 3, 8, 12, 19, 20 |
| `R/console-repl.R` | 2, 3, 7, 8, 13, 14, 15, 17, 18, 20, 21, 22, 24, 25, 26 |
| `R/console-interrupt.R` | 3, 13, 14, 15, 17, 18, 20 |
| `R/console-input.R` (new: key machine, live row, typing loop) | 16, 17, 18, 19, 20, 21 |
| `R/console-complete.R` (new) | 22, 23 |
| `R/utils-options.R` (`readline_answer()`, tty wrappers, `console_class()`) | 2, 3, 17, 18, 25 |
| `R/utils-conditions.R` (`console_colors()`, `console_style()`; `gptr_message_write()` clears and redraws the live row) | 8, 11, 17 |
| `R/eval-core.R` (an evaluation holds the console's colours; printed output as result rows, visual review) | 11 |
| `R/gptr-config.R` (`type_ahead` description) | 18 |
| `R/console-commands.R` (`/help`, `/context`), `tests/testthat/test-console-commands.R` | 26, 27 |
| `tests/testthat/test-console-{typing,ui,render,repl,completion,interrupt,wait,spinner-*,fences,jupyter-progress,message-stream,setup,notice,process-launch}.R`, `helper-console-input.R` | their tasks |
| `tests/testthat/test-cli-{codex,claude}.R` (expected tool lines), `fixtures/cli/claude-toolstream.ndjson` (rows) | 8, 10, 11, 12 |
| `tests/testthat/test-subagent-team.R`, `test-gptr-gateway.R` (expected sub-agent lines) | 11, 12 |
| `tests/testthat/test-console-input.R` (new, pure) | 16, 17, 19 |
| `tests/testthat/test-agent-{run,loop,dispatch}.R`, `fixtures/oracles/report02/loop.json`, `test-session-object.R`, `test-provider-transform.R` | 4, 5, 6 |
| `tests/testthat/helper-arch.R` (the console's contract edges; new files' layer rows), `test-arch-layers.R` | 15, 16, 22 |
| `tests/testthat.R` (CRAN list, D-240) | 16 |
| `dev/spec/03-architecture.md`, `dev/spec/04-interface-contract.md`, `dev/spec/05-plan-decomposition.md`, `dev/DEVIATIONS.md`, `?peter`, vignettes, README | 1, then each task's own sections, 27 |
| `dev/dogfood/p28-console.R` (new), `dev/progress/P28.md` | 1, 28, every task |

## Tasks

### Task 1: Plan, decisions and contract placeholders

Decisions:
- Add this plan. Register it as row 28 in `dev/plan/00-index.md` and in
  `dev/spec/05-plan-decomposition.md` (the row and the order line `... -> P27 -> P28`).
- `dev/progress/P28.md` holds a section per task, plus the evidence this plan uses:
  - audit scenarios A-I, with each one's key screen line and its REQ roles;
  - the Codex 0.157.1 observations (steer and queue preview, approval overlay, the `yes`
    fall-through, trigger-only popups);
  - the measured facts: cli 3.6.6 colour mapping, prompt markers on libedit, the drain check,
    the completion prototype, and the OSC 11/DA1 reply in tmux.
- Placeholders, marked pending:
  - D-242..D-245 in `dev/DEVIATIONS.md`;
  - 04 §15.10 "Codex-style console (IC-81, IC-82, 2026-10-21)";
  - amendment notes on IC-75, IC-76 and IC-77 that point to §15.10.
- D-242 gets its full text now (the steering table above), so later tasks build against it.

Tests, RED first: the cross-plan checks (`dev/research/assets/consolidation-tools/README.md`)
report `plan_not_in_decomposition` for P28 before its 05 row exists. They and
`python3 -I dev/ci/check-plans.py` pass after.

Files: `dev/plan/P28-console-codex.md`, `dev/plan/00-index.md`, `dev/spec/05-plan-decomposition.md`,
`dev/progress/P28.md`, `dev/DEVIATIONS.md`, `dev/spec/04-interface-contract.md`.

Commit: `docs(plan): P28 Codex-style peter() console`.

### Task 2: A question never takes typed-ahead text (the open bug; D-243, IC-76)

Root cause, from the audit:
- During a run the terminal is in canonical mode with echo off, and a partial line waits in the
  kernel buffer.
- The question's `readline()` leaves canonical mode, inherits that partial line, shows it after
  the prompt, and takes it as the answer:
  - B, F: lost as "Not an answer".
  - C: `no wait, ...` becomes a denial.
  - H: it becomes the answer to an ask-tool question.

Decisions:
- `console_before_message(kind = "prompt")` drains fd 0 before drawing a question, on a terminal
  REPL (today's IC-76 scope). Amended in the visual review: `ui_console_read()` drains just before its
  `readline()`, after the question's rows, so the lines it prints sit above `› ` instead of between a
  call's code and the flagged rows of its ask:
  1. Apply `stty -icanon min 0 time 0` (echo stays off).
  2. Read with `console_typed_lines(rd, 0L)` until nothing is left.
  3. Restore the saved modes.
  The mode change is one mockable wrapper, `tty_drain_mode()` (§7.1 row).
- Complete lines are routed as today. A trailing partial line goes to `console_history_add()`,
  with `[gptr] kept in history (↑): '<line>'` (amended in review: the echo is off while a run
  streams, so the notice quotes what was kept, and it promises no position; Task 15 uses the
  same form). Amended in the visual review: the line is the person's held text, dim at column 0
  like a queue line, `↳ kept in history ↑ · <line>`.
- In T class, Task 19 later replaces the history route with the composer draft. D class keeps it.
- These pty cases must pass on the Linux NOT_CRAN lane before Task 19 builds on the drain. On
  Linux the release of a partial line on leaving ICANON is reasoned from n_tty, not yet run.

Tests (`test-console-typing.R`), RED first:
- pure: `console_typed_split()` splits complete lines from a partial tail.
- pty B: `use base R` typed mid-stream without Enter, then an approval. The approval row ends
  with its prompt, `y` alone answers, and the notice names the kept line. Today the row ends
  `[?]: use base R`.
- pty C: a partial `no wait, plot it first` does not deny the call; REQ2 holds the tool's result.
- pty H: a partial line at an ask-tool question does not become `(typed) use base R`.

Spec: IC-76 (questions drain first), 03 §6.17.

Files: `R/console-render.R` (`console_before_message()`), `R/console-repl.R`
(`console_typed_split()`), `R/utils-options.R` (`tty_drain_mode()`),
`tests/testthat/test-console-typing.R`.

Commit: `fix(console): a question never takes typed-ahead text`.

### Task 3: A line typed before a question is queued, never dropped (D-243, IC-75)

Decisions:
- `readline_answer()` no longer discards a line returned in under 0.1 s (the existing stale rule,
  `the$readline_secs`, now the pure predicate `answer_stale(secs)`):
  - During a run, the line goes through `policy_enqueue(session, text, setting_get("type_ahead"),
    source = "repl")` and the question is read again (still at most 100 reads). A `/command` or
    `!code` line is routed as `console_typed()` routes it (amended in review): it waits in the
    reader for the next prompt and is never a steer (D-242).
  - Outside a run, the line goes to the history.
- This is the only lever in L consoles: RStudio and Windows hold typed lines until R reads.
- Layering (amended in Task 3): `readline_answer()` is in L0, which may not call the console (03 §2.2).
  It hands each line it reads past to a `keep` callback instead: the console questions pass
  `console_typed_ahead()` (`R/console-interrupt.R`, the routing above); the default is
  `console_history_add()` (moved to `R/utils-options.R`), so `gptr_confirm()` keeps it in the
  history; a secret input keeps nothing.
- An invalid answer and a pasted block are added to the history:
  - `Not an answer: '<text>' (kept in history).`, then the hint with the prompt's own letters
    `Type y, a or n (n <text> says what to do instead), or ?.`; an empty answer gets the hint
    alone (amended in review: the hint named a `p` the prompt never shows and had dropped the
    feedback form). Both are wrapped through `console_wrap()` at the width of the prompt's rows.
    The hint starts with the question, `Allow r? Type ...`, which may have scrolled away (amended in
    the visual review).
    This fixes the mid-word hard wraps in pty runs B, E and F.
  - `A pasted block is not an answer (kept in history).`
- No answer is ever guessed into a steer.

Tests (`test-console-ui.R`, `test-console-typing.R`), RED first:
- The stale-line case, which today discards the line, gives one queue item with source `repl`
  and a second read.
- The history mock receives the invalid answer and the paste.
- A 40-character invalid answer wraps inside the width.
- pty D: a complete line arriving just after the prompt is drawn reaches REQ2 as a relay.

Spec: IC-75 (stale rule, paste rule), 04 §7.1.

Files: `R/utils-options.R` (`readline_answer()`, `answer_stale()`, `console_history_add()`),
`R/console-interrupt.R` (`console_typed_ahead()`), `R/console-ui.R`, `R/console-repl.R`,
`tests/testthat/test-console-ui.R`, `tests/testthat/test-console-typing.R`.

Commit: `fix(console): a line typed before a question is queued, never dropped`.

### Task 4: Every queued steer reaches the next step boundary (backend 1; D-242)

Decisions:
- `run_take(run, "steer")` takes every item in the steer FIFO, in order. Each item becomes its own
  `queue_item_message()`: an operator relay once the run has made a request. Follow-ups are
  still taken one at a time.
- The `loop_new()` doc says "steering returns every queued steer".
- The provider adapters already hold operator messages until pending tool results are complete
  (`provider-transform.R`).
- The boundary is pinned as D-242 states: no call is skipped.

Tests (`test-agent-run.R`, `test-provider-transform.R`), RED first:
- Two steers enqueued during one tool call both appear in REQ2. Today the second waits for REQ3.

Pinning tests (green before and after):
- A steer sent during a final answer adds one request to the same run.
- A steer sent during the first of two calls in one response appears in REQ2 after both tool
  results. The second call ran.
- Two consecutive relays after tool results serialise in the anthropic, openai-completions,
  openai-responses and bedrock fakes.

Rewritten (amended in Task 4): report 02's oracles L11-L13 (`test-agent-loop.R`, `loop.json`) pinned
one steer per request ("gptr has no 'all' mode"). They now expect both steers in REQ2, as in Pi's
`all` mode, and the follow-up in REQ3.

Spec: 03 §6.2 (all steers at a boundary), 04 IC-55 note.

Files: `R/agent-run.R` (`run_take()`), `R/agent-loop.R` (doc), `tests/testthat/test-agent-run.R`,
`tests/testthat/test-provider-transform.R`, `tests/testthat/test-agent-loop.R`,
`tests/testthat/fixtures/oracles/report02/loop.json`.

Commit: `fix(agent): every queued steer reaches the next step boundary`.

### Task 5: queue_update names the item; `session_unqueue()` (backend 2 and 3)

Decisions:
- `queue_update` gains `op` (`"add"`, `"take"` or `"withdraw"`), `which`, `text` (the redacted
  text) and `source`. The counts `steer` and `follow_up` stay. It is emitted by
  `session_enqueue()` and `run_take()`.
- `session_unqueue(s, which = "steer")` removes and returns the newest item of `which` whose
  source is a user source, or NULL, and emits op `"withdraw"`. Extension and agent items are
  never touched.

Tests (`test-session-object.R`, `test-agent-run.R`), RED first:
- The payload on add and on take.
- `session_unqueue()`:
  - returns the newest user steer and emits withdraw;
  - leaves extension items;
  - returns NULL on an empty queue.

Spec: 04 §10.4 `queue_update` row, the `ext-events.R` catalogue.

Files: `R/session-object.R`, `R/agent-run.R`, `R/ext-events.R`,
`tests/testthat/test-session-object.R`, `tests/testthat/test-agent-run.R`.

Commit: `feat(session): queue_update names the item; session_unqueue() takes one back`.

### Task 6: Permission requests carry the tool call id (backend 4)

Decisions:
- `perm_request_record()` adds `tool_call_id = call$id`. Nested member calls inside `r` carry
  their own id.
- Why: the approval attaches to the call line the console printed (Task 12). Matching on name
  and input fails for parallel, nested and sub-agent calls.

Tests (`test-agent-dispatch.R`), RED first: `tool_call_id` equals the call id for a direct call
and for a nested member call.

Spec: 04 §7.11.

Files: `R/agent-dispatch.R` (`perm_request_record()`), `tests/testthat/test-agent-dispatch.R`.

Commit: `feat(perm): permission requests carry the tool call id`.

### Task 7: The step boundary reads typed input first (D-242)

Decisions:
- `builtin_console` subscribes `turn_end`. Its hook runs `console_typed()` once. `turn_end` is
  emitted in after_turn just before the loop polls steers, so a message sent before a boundary is
  in the FIFO when the loop looks. (Amended in review: no `policy_flush()`; `console_typed()`
  queues through `policy_enqueue()`, which flushes, and items held while a tool ran are flushed at
  its `tool_execution_end`.)
- This covers keys typed during an in-process `r` tool, which today reach the next boundary only
  if the 0.1 s task happens to tick in between.
- Front end only. D class benefits now; T class from Task 18.
- `console_typed()` checks `repl_terminal()` itself (amended in Task 7), so the hook reads nothing outside a
  terminal REPL (`.stdin`, jsonl, IDE consoles) and `console_before_message()` drops its own check.

Tests (`test-console-typing.R`), RED first: the fake provider with one slow in-process tool, a
mocked fd 0 that yields `and also use mtcars` only after the tool ran, and the periodic typing
task never ticking. REQ2 ends `tool_result,operator` with the relay. Today the relay arrives in
REQ3 or not at all.

Spec: 04 §7.14 hook list.

Files: `R/console-render.R` (`console_hooks()`, new `console_on_turn_end()`), `R/console-repl.R`
(`console_typed()`), `tests/testthat/test-console-typing.R`.

Commit: `fix(console): the step boundary reads typed input before steers are polled`.

### Task 8: One style table from the logo's cursor vocabulary (D-245, IC-82)

Decisions:
- `console_style()` replaces `console_symbols()` and holds glyphs, accents, dim and the band.
- Glyphs (UTF-8, then ASCII):

| role | UTF-8 | ASCII |
|---|---|---|
| person | `›` (U+203A) | `>>` (amended in the visual review: `> y` read as R's own prompt) |
| tool call | `▎` (U+258E) | `\|` |
| agent (working row, sub-agents) | `▌` (U+258C) | `#` |
| queued message | `↳` (U+21B3) | `->` |
| the Up key (history recall) | `↑` (U+2191) | `Up` (`^` reads as Ctrl) |
| question | `?` | `?` (the same in both, so `console_style()` does not hold it) |
| bullets | `•`, `◦` | `-` |
| separator | ` · ` | ` - ` |
| ellipsis | `…` | `...` |

- ASCII applies when `cli::is_utf8_output()` is FALSE, in Rgui, and on a Windows console outside
  Windows Terminal (no `WT_SESSION`, not RStudio). U+258E and U+21B3 are not in WGL4.
- Accents. One pair on every background:
  - At 256 colours or more: `cli::make_ansi_style("#b85450")` (logo red; cli gives `38;5;167`)
    and `cli::make_ansi_style("#557ea8")`.
  - `#557ea8` is logo blue `#6c8ebf` one step darker. cli gives `38;5;67`. Its contrast is
    3.8:1 on white and above 4:1 on #1c1c1c, where cli's 256-colour cell for `#6c8ebf` (110) is
    2.3:1 on white. These cli 3.6.6 numbers were measured.
  - At 8 or 16 colours: cli's `"red"` and `"blue"`. cli maps both blues to grey 90 there
    (measured).
  - At 1 colour: none.
- `dim` is the console's one grey; no console line uses cli's `col_grey()` (SGR 90), and the REPL adds no
  echo of an interpolated prompt to the gateway's notice (amended in the review of Tasks 8-15). At 256
  colours or more it is `#878787`, halfway between the logo's ink and cream (cli's cell 244), else SGR 2:
  RStudio and Positron draw SGR 2 in full ink (amended in the visual review).
- The band is `\033[48;5;237m` on a dark background or `\033[48;5;254m` on a light one. It needs
  at least 256 colours and a known background, and is otherwise empty. These are raw grey-ramp
  cells, because cli maps greys into the colour cube.
- `the$background` is `"dark"`, `"light"` or NA. It comes from `COLORFGBG` here
  (`console_background()`, read once); Task 25 adds the probe.
- The waiting row (`console_spinner()`) shows the agent's static block in place of its Braille
  frames (amended in Task 8), so none is left in `R/`; Task 17 replaces the row.
- Codex parity: Codex's composer fill is 12% white on dark and 4% black on light. Index 237 is
  its nearest cell on #1c1c1c.

Tests (`test-console-render.R`), RED first:
- Exact bytes for each depth (16777216, 256, 16, 1) and each background (dark, light, NA).
- `NO_COLOR` keeps the glyphs and drops all SGR. In the margin the Markdown is read at every depth, so
  a console without colour shows the text a colour console shows (amended in the visual review).
- ASCII with `is_windows()` mocked and `WT_SESSION` unset.
- No `U+25CF` and no Braille anywhere in `R/`.

Spec: IC-82 glyph and palette tables, 03 §6.17.

Files: `R/console-render.R` (`console_style()`, `console_background()`; moved to `R/utils-conditions.R`,
L0, beside `console_colors()` in the visual review, so the evaluator's display of printed output, L4,
uses the one style table), every caller of
`console_symbols()` and `cli::symbol$ellipsis` (`R/console-render.R`, `R/console-repl.R`,
`R/console-ui.R`), `tests/testthat/test-console-render.R`, and the tests that expect the old glyphs
(`test-console-{spinner-width,fences,jupyter-progress}.R`, `test-cli-{codex,claude}.R`). Amended in
Task 8: `console_class()` moves to Task 17, its first caller.

Commit: `feat(console): one style table from the logo's cursor vocabulary`.

### Task 9: R code in the logo palette; other code plain (D-245)

Decisions:
- The style table's `code` entry (`console_style()$code`, Task 8) is the R code theme. It maps:
  - reserved words and `function`: red;
  - strings, numbers and constants: blue;
  - calls: `"bold"`;
  - comments: the grey (`dim`'s colour);
  - operators and brackets: ink.
  Red and blue are chosen by depth, as in Task 8. (Amended in Task 9: an entry of the style table,
  not a separate `gptr_code_theme()`. cli takes a theme as colour names, so a separate function
  would repeat the depth rule and the two hex values.)
- R in tool calls and in answer fences is highlighted by `console_code()` with
  `cli::code_highlight(code, code_theme = getOption("cli.code_theme") %||% console_style()$code)`,
  so a user's theme wins.
- Highlighting runs only when `cli::num_ansi_colors() > 1`. Code that does not parse is shown
  plain. It adds no help links (`cli.hyperlink_help = FALSE`; amended in the visual review: RStudio
  underlined every call as a help link).
- `code_light()` (Solarized) is deleted. Other languages are shown in ink with dim fences.
- Inline code in an answer takes the blue accent, as strings do, not cli's cyan (amended in the review of
  Tasks 8-15).

Tests (`test-console-render.R`), RED first:
- An r fence and an r tool call's fence at 256 colours hold `38;5;167` on `function` and `38;5;67`
  on `"s"`; at 16 colours, `31` and `34`.
- A python fence holds no SGR.
- A user `cli.code_theme` wins.

Spec: IC-82, 03 §6.17.

Files: `R/console-render.R` (`console_style()$code`, `console_code()`, `code_light()` deleted),
`tests/testthat/test-console-render.R`, `tests/testthat/test-console-fences.R` (its
`code_highlight` mock takes the theme).

Commit: `feat(console): R code highlighted in the logo palette`.

### Task 10: The transcript is written in whole rows (D-245)

Decisions:
- `render_markdown_stream()` commits a row only at its newline or at its wrap (width - 4 in the
  margin, 100 columns at most; amended in the visual review: a maximised VS Code panel ran prose to 127
  characters) and holds the partial row. This is Codex's newline-gated `markdown_stream`.
- The `\r` redraw of fenced lines goes away.
- One mode everywhere, so no half line ever sits where the live row is drawn.
- Other output (a queue line, a notice, a question) goes between whole rows, and the held row continues after
  it: a typed line clears only the waiting row, keeping its clock, and pauses nothing. A queue line waits for
  an open text block to end and is a block of its own (amended in the visual review: between whole rows it
  still split a sentence). The pause menu, too, stops only the waiting rows; an abort still ends the
  stream (amended in the visual review). `reset_line()` is
  deleted (amended in the review of Tasks 8-15: a queued steer had ended the held row as a short row and
  restarted the waiting row at 0 s inside the answer).

Tests (`test-console-render.R`), RED first:
- Nothing is written for a row before it is complete. Today partial rows are written, and in the
  margin a fenced line's characters.
- The four-mode chunk-invariance test and the verbosity 0/1/2 equivalence stay green.
- 'fenced lines stream as they arrive' and 'a line ended by other output continues' are rewritten
  to whole rows. So are (amended in Task 10):
  - 'a fenced line broken by other output': it is written once, after that output;
  - the waiting-row tests, 'the spinner runs as a reactor task until the first rendered text' and
    test-console-wait.R's 'the first rendered output ends the waiting row, even a style alone':
    the waiting row stays until the first whole row.

Spec: 04 §7.14 (`render_markdown_stream` commits whole rows), 03 §6.17 (the Rendering item and
the fenced-code sentence).

Files: `R/console-render.R` (`render_markdown_stream()`, `console_stream_output()`'s description),
`tests/testthat/test-console-render.R`, `tests/testthat/test-console-wait.R`,
`tests/testthat/test-cli-claude.R` and `tests/testthat/fixtures/cli/claude-toolstream.ndjson`: the
fixture's three deltas become three rows, so the #31 streaming test still sees them arrive apart.
(Amended in Task 10: `test-console-fences.R` needs no change.)

Commit: `refactor(console): the transcript is written in whole rows`.

### Task 11: Tool calls as cursor strips by kind (D-245)

Decisions:
- `console_tool_kind(name, spec)` returns one of three kinds:
  - `"read"`: `annotations$read_only` (a trusted MCP server's `readOnlyHint` arrives as it);
  - `"agent"`: Codex's collab call, `codex_agent` (gptr's own sub-agents are `peter()` calls in `r`,
    shown by their lines);
  - `"act"`: everything else (r, shells, edit, write, other MCP and plugin tools, Codex's shells,
    file changes and web searches).
  (Amended in Task 11: no CLI route's Read, Grep, Glob, LS, Bash, Edit or Write reaches the
  console. The claude CLI runs with `--tools ""` and calls gptr's own tools over MCP, whose
  annotations decide; Codex reports shells, file changes, web searches, MCP calls and its collab
  call.)
- How each kind is shown:

| kind | line | style |
|---|---|---|
| read | `▎ read  R/plot.R` | whole line dim; no result line unless it fails |
| act | `▎ <name>  <first line>`, or the name over at most 20 code rows at column 4, each cut to the width (amended in the visual review: no fence lines, R highlighted on the one line too) | red strip, name bold |
| agent | `▌ sub-agent a (haiku) started`, `▌ sub-agent a done (1/3) · 4 turns · 12 s` | blue block |

- The tool name is always printed, so a kind never relies on colour alone.
- An MCP call shows its arguments dim: `▎ github/search_issues  {"q":"bug"}`.
- Results are indented 4 and dim (`+ fit · 1.2 s`, `done · 3.0 s`; the time from a second, as
  before). Errors are red, at most 6 rows. In the margin what the code prints is shown the same way, per
  top-level expression, not teed raw at column 0 (amended in the visual review).
- Tool rows of consecutive requests group as those of one response: a waiting row after a tool block
  takes no blank line and keeps the tool block open, and what else replaces it opens with the blank
  (amended in the review of Tasks 8-15: a run of reads was spaced or not by how the model batched
  them, which the person cannot see).
- Diffs: `+` lines blue and `-` lines red, at most 12; the file headers (`--- a/`, `+++ b/`) are left out,
  as the call line names the file, and hunk headers are dim (amended in the review of Tasks 8-15: Task 11
  showed the headers dim, two of the 12 rows). A row wider than the console is cut with `…`, never wrapped
  (amended in the visual review: wrapping collapsed the code's spaces and left a row without its sign).
- IC-69 `render()` still wins.
- A sub-agent's lines are drawn inside the agent's `r` evaluation, whose options say 1 colour, so
  the evaluation holds the console's colours beside its margin (`.gptr_console_colors`, read by
  `console_colors()`) and the line is styled in them (amended in Task 11).

Tests (`test-console-render.R`), RED first: each kind gives its exact bytes at 256 colours, under
`NO_COLOR` and in ASCII, and so do the result lines; a sub-agent started by the agent's r code
has the blue block. Today every kind prints an unstyled `▎ ` (`● ` before Task 8).

Spec: IC-82, 03 §6.17.

Files: `R/console-render.R` (`console_tool_kind()`, `console_call_line()`, `console_result_lines()`,
`console_tool_line()`, `console_child_line()`, `console_on_agent_start()`), `R/utils-conditions.R`
(`console_colors()`, and `console_eval_value()`, which `console_pad()` shares), `R/eval-core.R`,
`tests/testthat/test-console-render.R`, and the tests that expect the old lines
(`test-console-{message-stream,ui}.R`, `test-subagent-team.R`, `test-gptr-gateway.R`,
`test-cli-claude.R`), and the sub-agent line in `vignettes/teams-and-background.Rmd` (and `.orig`).
Amended in Task 11.

Commit: `feat(console): tool calls as cursor strips tinted by kind`.

### Task 12: Approvals ask under the call they gate (D-243, IC-77)

Decisions:
- `ui_permission_lines()` omits the call line when the console's last printed call line has the
  request's `tool_call_id` (Task 6). Otherwise it prints it: background asks, nested member
  calls, and non-foreground sub-agents.
  - The console keeps the session and call ids of the last call line it printed
    (`console_state()$last_call`, set by `console_on_tool_start()`), so ids repeated across sessions
    never match. The call line it prints is `  ▎ r  <first line>  (+N more lines)`, as the console's
    act line. Who asks moves to the question (amended in Task 12). The call line and the question name
    the tool as the console's call line does (`console_tool_name()`: an MCP tool as `server/tool`,
    its arguments dim; amended in the review of Tasks 8-15).
  - A question and the tool block it is asked in are one block (`console_gap()`): no blank line
    between a call line, its ask and its result lines (amended in Task 12).
- Flagged rows (at most 5, then `(+N more; ? shows all)`) and the `asks in every mode:` reason
  stay, dim at column 4 like the result rows, later flagged rows under the first's text. The `?`
  detail view lists the keys as the question does (`    y  yes`, the key bold, its words dim) and
  leaves out its code rows when the call line just above showed the code whole (amended in the review of
  Tasks 8-15; the RStudio dialog keeps them, without SGR).
- The question is at column 2, `? Allow <tool>?`, and the keys are a row of their own under its text, at
  column 4: `y yes · a always (session) · p always (project) · n no · ? more` (amended in the review of
  Tasks 8-15: on the question's row they wrapped at 80 columns for any tool name of 4 characters or more,
  and the wrapped `? more` read as a second question).
  - `?` is blue, the question bold, key letters bold and descriptions dim.
  - The keys row is 68 columns whatever the tool or who asks. In a narrower console it wraps between the
    options at column 4: no-break spaces keep a key with its words, and are written as spaces.
  - a and p are omitted when no rule is offered; typed anyway, they get
    `a and p are not offered: <why>; answer y, n or ?.`.
  - Who asks: `? sub-agent a: allow r?`.
  - The invalid-answer hint (Task 3) names the same letters, `p` among them.
- The answer prompt is `› ` at column 0, read with R's readline, echo on, Enter required.
- Answers are unchanged:
  - `y`, `a`, `p`, `n`;
  - `n <text>` denies with feedback;
  - `?` shows the detail view;
  - Ctrl-C aborts.
- A remembered answer adds one dim line naming the rule it adds:
  `    allowed r(fn:write.csv) for this session` or `... this project`. (Amended in Task 12: the plan
  said `allowed r for this session`, which reads as every `r` call being allowed.)
- Ask-tool questions, and every console choice and input, use the same frame:
  - `? <title>` (bold);
  - details dim under it (they were `  | ` rows, and `|` is now the ASCII tool strip);
  - numbered choices `    1  dplyr` (number bold);
  - the hint (dim, at column 4 under the title's text; amended in the visual review):
    `Choose a number, or type your own answer; Enter = base`; an input's
    `Enter = <default>`;
  - the `› ` prompt.
  The OAuth inputs drop the `: ` that ended their prompts (amended in Task 12). Each part word-wraps at
  the approval rows' width under its own text: the title's later rows at column 4, a choice's under its
  label (amended in the review of Tasks 8-15: agent questions are usually longer than a row, and the
  terminal broke them mid-word at column 0).
- Questions drawn inside an evaluation (a sub-agent's or a nested call's) take the console's
  colours, `rlang::local_options(cli.num_colors = console_colors())`, as Task 11's sub-agent lines
  do (amended in Task 12).
- No single-key answers and no terminal title. Codex 0.157.1 approved on `y` and appended `es`
  to the draft; gptr never takes single keys.

Tests (`test-console-ui.R`), RED first:
- After a printed call, no second call line appears; a sub-agent's call in the parent's `r` code
  is printed by its ask.
- The options text and wrapping are exact, and the bytes at 256 colours.
- The sub-agent prefix.
- The select frame, and the input frame.
- The remembered-scope line.
- The tests that expect the old prompt text are rewritten (amended in Task 12): the rest of
  `test-console-ui.R`, `test-console-{typing,render,wait,repl,setup}.R`, `test-cli-claude.R` and
  `test-subagent-team.R`; the pty cases wait for `Allow r?` and end with `pty_asked()`
  (`helper-console-input.R`), the chevron the child's locale shows.

Spec: IC-77, 03 §6.8.3, §6.17 and NS-1 (§10.1).

Files: `R/console-ui.R` (`ui_question()`, `ui_permission_lines()`, `ui_console_permission()`,
`ui_console_select()`, `ui_console_input()`), `R/console-render.R` (`console_state()`,
`console_on_tool_start()`: the last printed call ids; `console_gap()`), `R/auth-oauth.R` (the input
prompts), the tests above, and the approval sentences of `vignettes/interactive-console.Rmd` and
`vignettes/teams-and-background.Rmd` (and their `.orig`). Amended in Task 12.

Commit: `feat(console): approvals ask under the call they gate`.

### Task 13: A delivered steer shows as the person's line at its boundary (D-242, IC-76)

Decisions:
- `builtin_console` subscribes `queue_update`. A `"take"` of a user-source item prints `› <text>`
  at column 0: escaped, wrapped, and on the band (`console_style()$band`, known from `COLORFGBG`
  since Task 8; Task 25 adds the probe). It is printed when the loop takes the item, before the
  next request's output, at verbosity 2 for a foreground run, as a block of its own
  (`console_gap()` kind `"person"`). A follow-up the run still takes (until Task 14) shows the same
  way.
- In every class for now, queueing prints one dim line at column 0:
  - `↳ steer · <text>` or `↳ follow-up · <text>`; ASCII `-> steer - <text>`;
  - on CLI routes, a steer adds ` · after the CLI's answer`;
  - the text is escaped and cut to three rows ending in `…`;
  - inside an evaluation (the pause menu during `r` code) it has the console's colours.
- Both lines come from `console_person_rows()`: the glyph, then the text wrapped at the console
  width less one, later rows under the text. The queue line's cut also trims a row wider than that
  (one long word), so it never takes more than three rows.
- These lines replace the notices `[gptr] steering: ...` and `[gptr] follow-up queued: ...`. The
  pause menu's [s] and [f] use the same lines. A line a question read past is on screen after the
  question's chevron, so its line reads `↳ steer · not an answer` (amended in the visual review).
- Task 18 stops printing the `↳` line in T class, where the live row shows the queue.

Tests (`test-console-typing.R`, `test-console-interrupt.R`), RED first:
- The `›` cell precedes REQ2's streamed text; a message of two lines keeps its later row under the
  text.
- At 256 colours and a dark background each `›` row is on the band, and the queue line of a long
  steer is dim and cut to three rows at width 40.
- The queue lines replace the notice strings (`queue_line()`, helper-console-input.R).
- The pause menu's [s] prints the same line.
- Rewritten: the pty case 'a terminal: typed text shows once, in its notice' (now once queued and
  once delivered, never in the answer), pty D, the macOS paste case in `test-console-repl.R`, and
  the `!code` case in `test-console-ui.R`.

Spec: IC-76 texts, 04 §7.14, 03 §6.17.

Files: `R/console-render.R` (`console_hooks()`, `console_on_queue_update()`,
`console_person_rows()`), `R/console-interrupt.R` (`policy_enqueue()`),
`tests/testthat/test-console-typing.R`, `tests/testthat/test-console-interrupt.R`,
`tests/testthat/test-console-ui.R`, `tests/testthat/test-console-repl.R`,
`tests/testthat/helper-console-input.R`, the steering sentences of
`vignettes/interactive-console.Rmd` (and its `.orig`) and `?peter` (`R/console-repl.R`).
Amended in Task 13.

Commit: `feat(console): a delivered steer shows as the person's line at its boundary`.

### Task 14: A follow-up is the next prompt (D-242)

Decisions:
- In the REPL these are held in `rd$typed`, in the order typed, together with `/cmd` and `!code`
  lines:
  - D-class lines, and lines routed at questions (Task 3), when `type_ahead = "follow_up"`;
  - pause-menu [f];
  - Tab in T (from Task 18).
- "In the REPL" means while one of its prompts runs (`rs$sending`) and it is not piped (`.stdin`,
  `jsonl`). `policy_enqueue()` decides, so its callers (the typing task, a line a question reads
  past, the pause menu) are unchanged. A held message prints its queue line
  (`console_queue_line()`, Task 13's line), and its `input` event comes when it is sent. So do the
  held `/cmd` and `!code` lines, as follow-ups (a `!code` line with the lines that continue it as one
  entry), in place of `[gptr] after this answer: ...` (amended in the review of Tasks 8-15).
- In one batch, `console_typed_route()` puts the message after the held lines typed before its
  first line.
- After the run's status line, the REPL reads them first, echoes each as `peter> <text>` (a
  message of several lines keeps its rows), and runs each as its own run.
- A draft starting with `/` or `!` is always a follow-up. In the REPL this includes the pause
  menu's [s].
- Outside the REPL (a programmatic `peter()` paused with Ctrl-C), [f] keeps the session's
  follow-up FIFO, since there is no next prompt.
- `gptr_steer(as =)` is unchanged.

Tests (`test-console-typing.R`), RED first:
- `type_ahead = "follow_up"` gives two runs and two status lines. Today it is one run.
- `!x = 1`, then a follow-up `use x`, then `!y = 2`, typed in one batch, keep their order.
- The pause menu's [s] `!zz = 5` and [f] `then plot it` in the REPL are the next two prompts.
- The test 'type_ahead = "follow_up" queues the line for when the agent would stop' is rewritten.

Spec: 03 §6.2 and §6.17, IC-76.

Files: `R/console-repl.R` (`console_reader()`, `console_typed_route()`, `?peter`),
`R/console-interrupt.R` (`policy_enqueue()`, `console_queue_line()`),
`tests/testthat/test-console-typing.R`, the follow-up sentences of
`vignettes/interactive-console.Rmd` and the `type_ahead` row of `vignettes/configuration.Rmd`
(and their `.orig`). Amended in Task 14.

Commit: `feat(console): a follow-up is sent as the next prompt`.

### Task 15: Nothing queued is lost (D-242)

Decisions:
- In an interactive R only (amended in the review of Tasks 8-15): elsewhere (Rscript, knitr) there is no history
  and no next prompt, so `console_queue_left()` returns at once and the queue stays as the run left it.
- At `agent_end` of a foreground run (`console_queue_left()`) with status idle or `max_turns`, user
  steers still queued are taken with `session_unqueue()` and, with the steers `policy_flush()` still
  holds for the session, become follow-ups for the next prompt: in the REPL whose prompt runs (not
  piped) they are appended to the reader's `typed` lines, after the held lines. This covers runs that
  ended first or hit the cap. Elsewhere they stay queued for the session's next run, and
  `policy_flush()` never drops an item.
- After any other end (an abort, an error, a block or the budget), these are not sent:
  - the user items the abort moved to `dropped` (steers and follow-ups);
  - user steers still in the FIFO, and the items held while a tool ran;
  - held follow-ups, with the held `/cmd` and `!code` lines (the REPL's `typed` lines).
  They are listed once, `↳ kept in history ↑ · <a> · <b>` (Task 2's form, as amended in the visual
  review), and added to the history in that
  order (`console_keep()`, which the partial-line notice also uses). Nothing is auto-sent after an
  abort. Follow-ups in the FIFO (outside the REPL) stay queued after an error.
- The list follows the run's status line, then the blank row before the prompt; `[gptr] aborted; the
  session is kept.` is printed only where no status line said `aborted` (amended in the review of
  Tasks 8-15: it repeated the status line, after the list).
- The draft joins this list once the composer holds it (Task 20). Until then gptr holds no draft: a
  partial line stays in the terminal.
- The notices `dropped typed lines` and `dropped queued messages` are deleted.

Tests (`test-console-typing.R`, `test-console-interrupt.R`), RED first:
- An abort keeps the texts in the history mock, the dropped steer first, then the held lines, in one
  notice. Today they are dropped.
- After an error the queued steer is kept, not sent with the next prompt.
- A `max_turns` leftover steer is sent as the next prompt, as the user message of run 2.
- Rewritten: Ctrl-C at an approval keeps the held line, and a steer typed in a tool and then aborted
  is kept, never sent later.

Spec: 03 §6.2 (abort keeps queued text; the pause menu writes to stdout, fixing the doc drift) and
§6.17, IC-76.

Files: `R/console-interrupt.R` (`policy_flush()`, `policy_abort()`, `console_repl_prompt()`),
`R/console-render.R` (`console_on_agent_end()`, `console_queue_left()`), `R/console-repl.R`
(`console_send()`, `console_keep()`, `?peter`), `tests/testthat/test-console-typing.R`,
`tests/testthat/test-console-interrupt.R`, `tests/testthat/helper-arch.R` (the console's
`session_unqueue()` edge), the interrupt sentences of `vignettes/interactive-console.Rmd` (and its
`.orig`). Amended in Task 15.

Commit: `fix(console): queued messages are never dropped`.

### Task 16: The composer's key machine (pure; D-243)

Decisions:
- `console_compose(state, chars, now, enter_kind, complete)` returns the new state
  (`list(draft, esc, t)`) and at most one action, as a batch sends at most one message: NULL,
  `send(kind, text)`, `take_back` or `complete(candidates)`.
- Keys:
  - printable characters append to the draft;
  - DEL and BS delete the last character;
  - Ctrl-U clears the draft;
  - Ctrl-W deletes the last word;
  - `\r` or `\n` sends (`\r\n` and `\r` read as `\n`); a blank message is not sent.
- Tab, arriving as a batch of its own:
  - on a trigger word (Task 22), completes and never queues; nothing happens without a match;
  - otherwise, sends the other kind.
- `console_trigger(line)` gives the trigger word at the draft's end, or NULL: the last word of a
  `!` or `!!` line, a word starting with `@` or `peter$`, or a first word starting with `/`. A word
  ends at whitespace and readline's break characters, `!` among them. Task 22's
  `console_complete()` takes its word from it. `complete(draft, nchar(draft))` returns full
  words; their longest common prefix replaces the word when it is longer, else two or more give
  `complete(candidates)`.
- Up (`ESC [ A` or `ESC O A`, a batch of its own) on an empty draft takes back.
- Other escape sequences are dropped up to their final byte (0x40-0x7e). An incomplete sequence
  is held until `now` passes 50 ms, and a lone ESC is then dropped.
- Batch rule (IC-76's paste rule): in a read batch that holds a newline, the draft plus
  everything up to the last newline is one message of the Enter kind, with its newlines kept.
  The rest stays as the draft. A newline ends what DEL, Ctrl-U and Ctrl-W reach. Tab and Up act
  only as a batch of their own: in any other batch Tab is text and Up is dropped.
- `/` and `!` drafts send as follow-ups.
- No cursor movement: the draft is edited at its end, and Left, Right, Ctrl-A and Ctrl-E are
  dropped. Full editing is readline's, at the prompt.

Tests (new `test-console-input.R`; it joins the CRAN list in `tests/testthat.R`), RED first: a
table of byte strings with the expected draft and actions covers:
- UTF-8 and wide characters;
- held, completed and dropped escape sequences, at 0 and 60 ms;
- the paste batch;
- Tab on trigger and non-trigger words;
- `/` and `!` drafts.

Spec: IC-76, 03 §3.2 (the new file's row).

Files: `R/console-input.R` (new), `tests/testthat/test-console-input.R` (new), `tests/testthat.R`,
`tests/testthat/helper-arch.R` and `tests/testthat/test-arch-layers.R` (the layer row, 123 files).

Commit: `feat(console): the composer's key machine`.

### Task 17: One live row for status, queue and input (D-243)

Decisions:
- `console_live()` replaces `console_spinner()`, with `draw(state)` and `clear()`.
- Row format (T): `▌ <state> <elapsed>[ · <n> queued][ · question waiting]   › <draft tail>`.
  - `<state>` is `thinking`, the running tool's name, or `sub-agent a`.
  - `<elapsed>` is shown as 0s, 59s, 1m 05s.
- With an empty draft, the hint follows instead of `›`:
  - with a queue: `↳ <kind> · <newest text> · ↑ edit`;
  - otherwise: `enter steer · tab follow-up · ctrl-c pause`, swapped when
    `type_ahead = "follow_up"`.
- Completion candidates (Task 22) replace the status words until the next key, so the terminal
  cursor stays at the end of the draft.
- One collapse rule: cut the status part from the right with `…`, down to `▌ <elapsed>`. The
  draft keeps its tail.
- Writing:
  - T: `\r` + band + row + `\033[K\033[0m`, cut to `console_width() - 1` by
    `cli::ansi_nchar(type = "width")`, with ambiguous widths counted as 2 (amended in Task 17: every
    character outside ASCII that R counts as one column counts two, `live_fit()`; R has no ambiguous-width
    table, and a draft's Greek or accented letters are as likely to be drawn wide).
  - Redrawn on every key and once a second. The block is static (no blink, no spinner).
  - The block is the agent's blue, the status words and hints dim; only the draft is ink (amended in the
    visual review: the waiting row's ink block and ink sentence were the loudest row on screen).
  - At column 0, under the transcript's last row, from a run's first request to its end; no block, so
    `console_gap()` loses its waiting kind and the next block writes its blank on the cleared row (amended in
    Task 17).
- Every `gptr_message_write()` first writes `\r\033[K` (amended in Task 17: not `\r\033[0m\033[K`; the row
  ends its own band with `\033[0m`, and NO_COLOR writes no SGR), then its whole lines, then redraws the
  row (`the$live_row`, at the sink the row was drawn at; 03 §2.2 rule 5). Where the row is padded, or after a
  partial line, the first write ends it until the run next waits (amended in Task 17: a padded row redrawn
  after every write left its spaces on every transcript row). A question or a launched process clears it
  (`console_before_message()`); notices, queue lines and sub-agent lines are written with it cleared and
  redrawn (amended in Task 17: they no longer hide it; `console_typed_route()` no longer clears it).
- L: status only, `\r` + text + `\033[K` in RStudio, which honours it, padded with spaces to width - 1
  only where it is unknown (Rgui), ending `· esc stops` (RStudio, Rgui) or
  `· ctrl-c pauses` (Positron). (Amended in the review of Tasks 16-21: R.app draws no row. Written as a run's
  first output, a row starting with `\r` gave the whole transcript the input's colour there, and its `\r` erases a
  line printed just before it.) (Amended in the visual review: the padding left about 57 trailing
  spaces on each RStudio row that replaced the waiting row.) D (TERM=dumb) is padded too, and so is
  Positron, whose console erases by writing spaces (amended in Task 17: given `\033[K`, its transcript had
  32 rows ending in spaces). Until Task 18's composer reads keys, T is status only as well, ending
  `· ctrl-c pauses` (amended in Task 17).
- P: nothing.
- `console_class()` takes no argument (amended in Task 17): P outside an interactive R; a piped REPL
  (`.stdin`) stays out of `repl_terminal()`, which is now a T or D console's REPL not piped, so radian (L in
  the class table) no longer has its typed lines read from fd 0.

Tests (`test-console-input.R`, `test-console-wait.R`, `test-console-spinner-*.R`), RED first:
- Exact rows per class and width (80, 40, 30).
- A notice write is wrapped in clear and redraw.
- The spinner text 'thinking (Ns, Ctrl-C to steer or stop)' goes (Task 8 replaced its Braille
  frames).

Spec: IC-82 live-row format, 04 §7.14.

Files: `R/console-input.R` (`console_live()`), `R/console-render.R` (`console_spinner()` deleted),
`R/utils-options.R` (`console_class()`), `R/utils-conditions.R` (`gptr_message_write()`),
`tests/testthat/test-console-input.R`, `tests/testthat/test-console-wait.R`,
`tests/testthat/test-console-spinner-gui.R`, `tests/testthat/test-console-spinner-width.R`. Amended in
Task 17: also `R/console-repl.R` (`repl_terminal()`, `console_typed_route()`), `R/console-interrupt.R`
(`policy_menu()` clears the row), the wording of `R/console-ui.R` and `R/cli-common.R`, the tests that
held the waiting row (`test-console-{notice,process-launch,fences,render}.R`,
`test-compaction-acceptance.R`), the helpers
`local_live_console()`, `written()` and `term_rows()` in `helper-console-input.R`, 03 §2.2 rule 5 and
§6.17, and 04 §7.14 (the row of `console_live()`).

Commit: `feat(console): one live row at the bottom for status, queue and input`.

### Task 18: Type, steer and queue while the agent works (T class; D-243, IC-76)

Decisions:
- Terminal modes:
  - In T, `console_send()` sets `stty -icanon -echo -iexten min 1 time 0`:
    - isig stays on, for Ctrl-C (amended in the review of Tasks 16-21: `-isig` too, and Ctrl-C is a
      key the composer reads, after the keys before it in the batch, which interrupts as SIGINT
      would (`rlang::interrupt()`, so the pause menu resumes); the idle editor keeps the draft on
      it. Under load a SIGINT was lost in 6 of 19 runs at load average 40-57, during a streamed
      answer and at the idle editor. isig is on while in-process R code runs (`eval_open()`,
      `tty_isig_on()`), so Ctrl-C interrupts the code; questions read with the saved modes;
    - opost stays on;
    - `min 1` means a tool reading stdin blocks and does not see EOF.
  - D keeps `-echo`.
  - The saved modes are restored on return, error and interrupt.
  - `reg.finalizer(<state env>, onexit = TRUE)` also restores them at `q()`. Only a kill or a
    crash leaves `stty sane` to the person (`?peter`).
  - Character mode is never set when `RADIAN_VERSION` is set.
  - (Amended in Task 18:) `tty_call(keys)` in `R/utils-options.R` saves and sets the modes, and
    `tty_restore()` restores them once. `the$tty` (an environment with `saved`, `set` and `keys`)
    replaces `the$tty_modes`. Each call's `the$tty` is new and carries the finalizer, which does
    nothing once its modes are restored.
- `console_typed()` runs every 0.05 s. It reads `conn_read_chars()` from the existing fd-0
  connection, feeds `console_compose()` and carries out the actions:
  - a steer goes through `policy_enqueue()`;
  - a follow-up goes to `rd$typed`;
  - `take_back` takes the newest undelivered message from `rd$typed`, the console's held items,
    or `session_unqueue()`.
  - (Amended in Task 18:) `console_typed_chars()` is the read that `console_typed_lines()` splits.
    `console_keys(rd, s, chars)` in `console-input.R` carries out the actions, and
    `console_newest(s, rd, take)` finds the newest message. Across the two kinds, the newest is of
    the kind the composer sent last (`rd$sent`), because `rd$typed` keeps no send time. Tab
    completes nothing until Task 22.
- In T the `↳` queue line is not printed; the live row is the queue view. (Amended in Task 18:)
  This applies while the row is up. Where the row is cleared, as under a question, the line is
  printed.
- (Amended in Task 18:) A question's drain in T gives what waits on fd 0 to the composer. A partial
  line therefore stays the draft, where Task 2 kept it in the history.
- (Amended in Task 18:) A draft left when the REPL returns to its prompt (no follow-up left to send)
  goes to the console history. It is listed after the status line (`console_queue_left()`) until
  Task 21 continues it at the prompt. After an abort it joins the kept list, which was Task 20's.
- `gptr_readline()` reads with the saved modes and re-applies character mode afterwards.
- The `type_ahead` description in `R/gptr-config.R` and 04 §11.2 becomes: "What Enter does with
  a message typed in a terminal console while the agent works (Tab does the other); in other
  consoles, what a typed line does." The `type_ahead` row of the configuration vignette says the
  same.

Tests (`test-console-typing.R`), RED first:
- stty log `-g`, then `-icanon -echo -iexten min 1 time 0`, then SAVED.
- Modes restored after an error and an interrupt.
- No character mode with `RADIAN_VERSION` set.
- pty: the draft is visible on the live row while text streams.
- pty: Enter steers (REQ2 roles end `tool_result,operator`).
- pty: Tab gives a second run.
- pty: Up takes back and Ctrl-U discards.
- 'a terminal: typed text shows once, in its notice; ...' is rewritten for the live row.
- (Amended in Task 18:) The pty Enter, Tab and Up cases share two children. Case B now finds its
  text kept after the run, not under the question. Pure cases cover Up's order and a draft kept at
  the prompt and after an abort.

Spec: IC-76, D-221 (kept for D class), 04 §7.1 and §11.2. (Amended in Task 18:) Also 03 §6.17 and
D-243's Task 18 note.

Files: `R/console-input.R`, `R/console-repl.R` (`console_send()`, `console_typed()`),
`R/utils-options.R` (`gptr_readline()`, tty wrappers), `R/gptr-config.R`,
`vignettes/configuration.Rmd` (`type_ahead` row), `tests/testthat/test-console-typing.R`. (Amended
in Task 18:) Also `R/console-interrupt.R` (`console_queue_line()`), `R/console-render.R`
(`console_queue_left()`), `tests/testthat/helper-console-input.R` (`local_no_fd0()` mocks
`console_typed_chars()`) and the macOS paste case in `tests/testthat/test-console-repl.R`, whose
steer now shows on the live row and whose Ctrl-D is no composer key.

Commit: `feat(console): type, steer and queue while the agent works`.

### Task 19: A question waits for typing to pause and keeps the draft (T class; D-243)

Decisions:
- In T, before the question's rows are drawn (`console_before_message(kind = "prompt")`; D keeps
  Task 2's drain in `ui_console_read()`, after the rows, as amended in the visual review):
  1. Drains fd 0 into the composer.
  2. Keeps reading every 0.05 s while the last key is under 1 s old. The live row shows
     `question waiting`, and Enter and Tab still queue.
  3. Clears the row and prints the question.
  4. Reads the answer with the saved modes. (Amended in the review of Tasks 16-21: a read that Ctrl-C or
     an end of input ends first ends the person's row in a terminal, `ui_console_read()` and `console_ask()`.)
  5. Re-applies character mode and redraws the draft unchanged.
- (Amended in Task 19:) `console_ask_wait()` in `console-input.R` does steps 1 and 2, the last key
  being the composer's `rd$compose$t` and the row's `question waiting` the record's `question`.
  `gptr_readline()` re-applies the modes (Task 18). `console_asked()`, on exit of
  `ui_console_permission()`, `ui_console_select()` and `ui_console_input()`, redraws the row: after
  each read, a question that asks again (an invalid answer, a paste) would draw and clear it
  between its rows and its chevron.
- The ask appears 1 s after the last key, or at once when no key came in the last second. The
  rule is the pure `ask_ready(last_key, now)`.
- This replaces Task 2's history route in T.
- Sub-agent questions work the same way, one at a time. Typed messages always go to the parent
  session.

Tests (`test-console-input.R`, `test-console-typing.R`), RED first:
- `ask_ready()` timings.
- pty B in T: the text stays the draft and the approval row ends `› `.
- pty: `yes` typed 0.5 s before an ask does not answer it, and the ask is drawn at least 1 s
  after the last key.
- (Amended in Task 19:) `yes` is typed key by key, 0.3 s apart, as the ask comes due, then Enter,
  which queues it as a steer; the live row shows `question waiting`. The fake provider's call
  deltas made a fixed lead time unreliable. Case B also finds the draft on the row while the
  approved call runs.

Spec: IC-76, IC-77. (Amended in Task 19:) Also IC-82 (`question waiting`), 03 §6.17 and D-243's
Task 19 note.

Files: `R/console-input.R` (`ask_ready()`), `R/console-render.R` (`console_before_message()`),
`tests/testthat/test-console-input.R`, `tests/testthat/test-console-typing.R`. (Amended in Task 19:)
Also `R/console-ui.R` (`console_asked()` on exit of the three questions, and the doc of
`ui_console_read()`).

Commit: `feat(console): a question waits for typing to pause and keeps the draft`.

### Task 20: A draft survives Ctrl-C and the pause menu (T class; D-243)

Decisions:
- SIGINT flushes the kernel's unread input but never gptr's draft.
- The pause menu is a console question in every class (amended in the visual review: it was the one
  control outside the console's vocabulary, `[gptr] paused sf1a5079fab: [s]teer, ...` read at `  ? `):
  `  ? Paused`, then under its text a keys row built as the approval's,
  `    s steer · f follow-up · c continue · a abort · b background` (keys bold, words dim, wrapping
  between the options); the session id only when more than one session is paused; no
  `[gptr] continuing`; an invalid key gets a dim hint naming the keys. (Amended in Task 20:) A key or its
  word answers, as an approval reads `y` or `yes`, and an empty answer continues. Before, any text's first
  letter was its key, so a steer typed at the new chevron (`add a legend`) aborted the run. The keys row is
  `ui_keys()` in `console-ui.R`, which the approval uses too; its separator ends a row, never starts one.
- It is read with readline at `› ` at column 0 (`console_ask()` without the margin) with the saved
  modes.
- [s] and [f] read their text at the same `› ` and queue it exactly as Enter and Tab do. (Amended in
  Task 20:) `policy_enqueue()` keeps the reader's `sent`, the kind queued last, which `console_keys()`
  kept, so Up takes back a menu message as a composer one; blank text queues nothing, without the
  `[gptr] nothing queued; continuing` notice. Its queue line sits right under the menu's chevron, as under
  an approval: the records' last block is `prompt` while the menu is up and `notice` once it resumes.
- The draft is redrawn after the menu (amended in Task 20: at once, by `console_asked()` after
  `console_render_resume()`). After [a] it joins Task 15's kept list (`console_keep()`; done in Task 18).

Tests (`test-console-typing.R`, `test-console-interrupt.R`), RED first: pty G, a partial draft then
Ctrl-C [c], keeps the draft. Today it is lost. The menu's rows at 80 and 60 columns, at 256 colours
and in ASCII. (Amended in Task 20:) Since Task 18 the composer kept the draft through the menu, so pty G
is red on the menu's rows and `[gptr] continuing`, and its draft then steers the run. The approval's
keys row at 256 colours (`test-console-ui.R`) moves the separator's trailing space out of the dim span,
and INFRA-03 waits for `Paused` and the chevron.

Spec: 03 §6.2 pause menu, IC-76. (Amended in Task 20:) Also 04 §7.14 (`with_interrupt_policy()`'s
menu) and D-243's Task 20 note.

Files: `R/console-interrupt.R` (`policy_menu()`, `console_ask()`), `R/console-input.R`,
`tests/testthat/test-console-typing.R`, `tests/testthat/test-console-interrupt.R`. (Amended in Task 20:)
Also `R/console-ui.R` (`ui_keys()`), the reader's doc in `R/console-repl.R` and
`tests/testthat/test-console-ui.R`.

Commit: `feat(console): a draft survives Ctrl-C and the pause menu`.

### Task 21: A draft left at run end stays in the composer until sent (T class; D-243)

Decisions:
- When a draft is left, `rd$read(prompt)` draws the prompt (with the band) and the draft, then
  edits it with the composer keys in character mode until one of these (this replaces Task 18's
  history entry for a draft left after an idle end):
  - Enter returns the line as readline would. `/`, `!`, fences and continuation reads go through
    readline as usual.
  - The draft becomes empty, and readline takes over at the same prompt.
  - Ctrl-C adds the draft to the history, and readline takes over (Codex's rule).
- Up and Ctrl-D do nothing. Tab completes trigger words.
- The person is never cut off mid-word, and there is only one idle editor at a time.
- (Amended in Task 21:) `console_idle(rd, prompt)` in `console-input.R` is the editor. Its row is the
  prompt and the draft's tail, cut as the live row cuts it; it reads fd 0 with no time limit. Enter
  returns the line, and the reader echoes it as it echoes a follow-up, so the transcript keeps the whole
  line. Tab on any other word does nothing. Ctrl-C, or an end of input, lists the kept draft
  (`console_keep()`), and that Ctrl-C is not the first of the two that leave. After an idle or max_turns
  end, `console_queue_left()` leaves the draft in the composer, so it waits through the follow-ups' runs.
  Until Task 25 bands readline's prompt, only the editor's row has the band.

Tests (`test-console-input.R`, `test-console-typing.R`), RED first:
- Pure reader cases for Enter, emptying the draft and Ctrl-C.
- pty I: a draft typed during the run continues at the prompt and Enter sends it.
- (Amended in Task 21:) pty I also has Ctrl-C keep the draft and Up recall it. Pty B, C and H find each
  draft at the prompt, not `kept in history`, and Ctrl-U clears it. The macOS paste case in
  `test-console-repl.R` finds `peter> half` at the prompt. The pure Task 18 case now sends its draft
  from the prompt.

Spec: IC-76. (Amended in Task 21:) Also 03 §6.17 and D-243's Task 21 note.

Files: `R/console-input.R`, `R/console-repl.R` (`console_reader()`),
`tests/testthat/test-console-input.R`, `tests/testthat/test-console-typing.R`. (Amended in Task 21:)
Also `R/console-render.R` (`console_queue_left()`) and `tests/testthat/test-console-repl.R`.

Commit: `feat(console): a draft left at the end of a run stays until sent`.

### Task 22: Completion only after @, !, / and peter$ (terminal R; D-244, IC-81)

Decisions:
- `console_complete(line, end)` finds the word holding the cursor: whitespace-delimited, also
  split at readline's break characters (Task 16's `console_trigger()` on the text before the
  cursor, which also says whether it is a trigger word). It returns full words:

| line or word | candidates |
|---|---|
| line starting with optional spaces then `!` or `!!` | R's own completion of the code, or the caller's completer |
| word starting with `@` | visible objects, then files and directories (directories end in `/`), all `@`-prefixed; `a@b.com` gives nothing |
| word starting with `peter$` | peter's member names |
| word `@obj$...` | `names(obj)` or `.DollarNames(obj)` |
| first word starting with `/` | the registry's commands, `/skill:<name>`, plugin commands |
| anything else | `character(0)`: natural language, `$5`, a bare `$name`, `x$y`, `wow! x` |

  - R's own completion for `!` lines: `getFromNamespace(".completeToken", "utils")()` with
    `custom.completer` set to NULL around the call. This works on R 4.2 and later whatever the
    function's formals, with no `:::` NOTE.
  - A bare `$name` has no meaning in the REPL grammar, so it completes nothing.
- Adapter: one function `f(env)`.
  - It sets `env$fileName = FALSE` and `env$comps = character()` first, inside `tryCatch`. A
    missing `fileName` aborts the `readline()` call (verified).
  - It returns candidates relative to the host's token:
    `substring(cands, 1 + nchar(word) - nchar(env$token))`.
- Installing it:
  - `utils::rc.options(custom.completer = f)` only around the REPL's own prompt reads (`peter>`
    and its continuation reads), behind a flag.
  - It is restored with `on.exit` from `rc.getOption()`.
  - Not installed when `R_COMPLETION=FALSE`. A caller-owned completer is kept and called for `!`
    lines.
  - Questions, the pause menu and tool `readline()` calls get nothing.
  - The `!` word break stays.

Tests (`test-console-completion.R`), RED first:
- The trigger table, through utils' `.assignLinebuffer`, `.assignEnd`, `.guessTokenFromLine`,
  `.completeToken` and `.retrieveCompletions` (via `getFromNamespace`).
- The missing-`fileName` guard.
- The caller-owned completer.
- pty: `summarise the da` + Tab leaves the line unchanged; `@mtc`, `/mo` and `!summ` complete.

Spec: IC-81, 03 §6.17 completion bullet (amends D-183), 03 §3.2 (the new file's row).

Files: `R/console-complete.R` (new), `R/console-repl.R` (`repl_main()`, `console_reader()`),
`tests/testthat/test-console-completion.R`, `tests/testthat/helper-arch.R` and
`tests/testthat/test-arch-layers.R` (the layer row).

Commit: `feat(console): completion only after @, !, / and peter$`.

### Task 23: Trigger-only completion in RStudio and Windows consoles (D-244, IC-81)

Decisions:
- Windows Rterm and Rgui complete through `utils:::.win32consoleCompletion()`, which honours
  `custom.completer`, so the same adapter applies.
- RStudio consults `custom.completer` before its own engine. An empty result means no popup, also
  for the automatic one after 3 characters and 250 ms.
- RStudio's editor shares that RPC while `peter>` waits. When
  `dynGet("isConsole", ifnotfound = NA)` is FALSE, the request came from the editor, which gets R's
  default completion (the NULL-completer path).
- gptr never writes RStudio preferences. `?peter` names `insert_matching` and
  `console_code_completion`.
- `@path` replacement in RStudio's popup is not promised.
- Positron, radian and R.app are out of reach and documented.

Tests (`test-console-completion.R`), RED first:
- `.win32consoleCompletion()` (via `getFromNamespace`) on the trigger table.
- An RStudio-sequence replay inside a frame binding `isConsole` TRUE (triggers only) and FALSE (R
  completion).
- 'unsupported input modes and IDE consoles keep completion options unchanged' is rewritten: IDE
  consoles get the scoped completer.

Spec: IC-81.

Files: `R/console-complete.R`, `tests/testthat/test-console-completion.R`.

Commit: `feat(console): trigger-only completion in RStudio and Windows consoles`.

### Task 24: !, / and @ show what they do (D-244)

Decisions:
- In the composer (T, during runs and in the idle composer):
  - a leading `!` replaces the glyph `›` with a bold red `!` (Codex's shell mode);
  - a leading `/` or `!` sets the hint to `runs after this answer`.
  Plain text is never restyled.
- After any prompt is sent (all classes), one dim line at column 2 names what the mentions
  resolved to: `@ mtcars_copy (data.frame, 32 x 11) · @ notes.md (first 40 lines) · @fit2 not
  found, sent as text`. It reuses `repl_mentions()`.
- Readline's echo is not restyled while the person types: there is no per-key hook. The composer
  does no per-token colouring either, so text looks the same at every phase.

Tests (`test-console-input.R`, `test-console-repl.R`), RED first:
- The `!` row bytes and the hint.
- The mention line for an object, a file and a missing name.
- No line for a prompt without `@`.

Spec: 03 §6.17 grammar.

Files: `R/console-input.R`, `R/console-repl.R` (`repl_turn()`, `repl_mentions()`),
`tests/testthat/test-console-input.R`, `tests/testthat/test-console-repl.R`.

Commit: `feat(console): !, / and @ show what they do`.

### Task 25: A shaded input band where the background is known (D-245, IC-82)

Decisions:
- Probe, once per REPL in T:
  1. Set `stty -icanon -echo min 0 time 0`.
  2. Write `ESC ] 11 ; ? ESC \` and DA1 `ESC [ c`.
  3. Read fd 0 until the DA1 reply `ESC [ ? ... c` arrives, at most 250 ms.
  4. Parse `rgb:RRRR/GGGG/BBBB` (BEL or ST, 2- or 4-digit hex). Luminance below 0.5 means dark.
  5. Restore the modes.
- The probe is skipped for TERM=linux or dumb, `NO_COLOR`, fewer than 256 colours and non-tty
  output. Otherwise `COLORFGBG` decides: 0-6 or 8 is dark; 7 or 9-15 is light. Otherwise the
  background is unknown and there is no band.
- The probe and the mode change are mockable wrappers (§7.1).
- Idle prompt (T, band known): `\001<band>\002peter> \001\033[K\002`.
  - After every read, `\033[0m\033[K` is written, also from `on.exit`. This resets attributes and
    erases the band that background-colour-erase put on the next line.
  - Continuation prompts get the same band.
  - Verified on libedit in tmux: the band filled while typing and through edits, and stayed on
    the submitted row. The second row of a wrapped input is shaded only under its text; this is
    accepted.
  - GNU readline 8.x is covered by the Linux pty case.
- The live row, delivered steers (`› text`) and follow-ups echoed at `peter> ` use the same band,
  so everything the person wrote looks the same.
- The band never appears in RStudio (no SGR in prompts), on Windows, in D or P, or under NO_COLOR.

Tests (`test-console-repl.R`, `test-console-input.R`), RED first:
- The reply parser: BEL and ST, 2- and 4-digit hex, DA1 only, timeout.
- `COLORFGBG` cases.
- pty: the prompt bytes and the reset appear.
- No band for an unknown background, 16 colours, `NO_COLOR`, or RStudio or Windows (mocked).

Spec: IC-82, 04 §7.1.

Files: `R/console-repl.R` (`repl_prompt()`, `console_reader()`), `R/console-render.R`
(`console_style()`), `R/utils-options.R` (probe and mode wrappers),
`tests/testthat/test-console-repl.R`, `tests/testthat/test-console-input.R`.

Commit: `feat(console): a shaded input band where the background is known`.

### Task 26: Run status names the model and the context left (D-245, IC-77)

Decisions:
- The run-end line is dim at column 2:
  `done · <model> · <n> requests · <tokens> tokens · <cost> · <k>% context left`.
  - Instead of `done`: `aborted: <reason>` or `error: <reason>`.
  - The model is the run's last request's model.
  - The line wraps like any notice.
  - A term whose value is unknown (`unknown tokens`, `unknown cost`), or a cost of 0 (a free or local
    model), is left out: `aborted · 1 request` (amended in the visual review: `$0.0000`, and two unknown
    terms after an abort, were noise). `format_cost()` stays as IC-74 has it for `/cost`.
- `console_context_left()` computes `1 - (input + cache_read + cache_write)` of the last request
  divided by the limit:
  - the limit is `compact_threshold(window, max_output)` when finite, else the model's window;
  - the term is omitted when neither is known, and on CLI routes;
  - `/context` uses the same helper.
- Banner, three dim lines at column 2:
  - `gptr <ver> · <model> · <mode> · .gptr/ found`
  - `objects: <up to six>`
  - `/help lists commands · tab completes after @ ! / · ctrl-c twice leaves`
  The keys in the banner are bold. Ctrl-C does not pause at idle, so the banner does not say it
  does. The key is the console's own (`console_interrupt_key()`, lower case: `esc twice leaves` in
  RStudio, R.app and Rgui), and no line promises a pause where the menu is not offered (amended in the
  visual review: the banner said `Esc pauses an answer` where Esc stops the run).
- The mode stays in the prompt (`peter[auto]>`). Shift-Tab is not added; readline cannot bind it
  portably.

Tests (`test-console-render.R`, `test-console-repl.R`, `test-console-commands.R`), RED first:
- The status text.
- The context arithmetic against `compact_threshold()`.
- The CLI omission.
- The banner bytes.
- `/context` agrees.

Spec: IC-77 run totals (amends D-206), NS-1 banner.

Files: `R/console-render.R` (`console_status_line()`, `console_context_left()`), `R/console-repl.R`
(`repl_banner()`), `R/console-commands.R` (`/context`), `tests/testthat/test-console-render.R`,
`tests/testthat/test-console-repl.R`, `tests/testthat/test-console-commands.R`.

Commit: `feat(console): run status names the model and the context left`.

### Task 27: Documentation (D-242..D-245 final)

Decisions:
- Update `?peter`:
  - keep the name rationale;
  - the two kinds of queued message and the keys;
  - the front-end table;
  - the CLI-route and L-console limits;
  - `insert_matching`;
  - `stty sane`.
- Update `/help`, the interactive-console vignette and the README console section.
- Finalise D-242..D-245, §15.10 and the amended IC-75..IC-77.
- Re-run the cross-plan checks.
- Update report 18's Verification log rows for type-ahead, completion and the band.

Tests, RED first: a new expectation in `test-console-commands.R` that `/help` names Enter, Tab,
Up, the two kinds and the trigger characters fails until `/help` is updated. Then
`devtools::document()` leaves no diff and `R CMD check --as-cran` on the built tarball passes.

Files: `R/gptr-gateway.R` and `R/console-repl.R` roxygen (`?peter`), `R/console-commands.R`
(`/help`), `vignettes/interactive-console.Rmd`, `README.Rmd`, `README.md`, `dev/DEVIATIONS.md`,
`dev/spec/03-architecture.md`, `dev/spec/04-interface-contract.md`, `dev/research/18-*.md`
Verification log, `tests/testthat/test-console-commands.R`.

Commit: `docs(console): the Codex-style peter() console`.

### Task 28: Live dogfood and evidence

Decisions:
- Add `dev/dogfood/p28-console.R`. Setup:
  - `GPTR_LIVE_TESTS=true`;
  - terminal R in tmux 100x32, keys sent with `tmux send-keys` 40 ms apart;
  - snapshots with `capture-pane -e -N`;
  - gptr settings isolated in temporary R_USER_* directories. HOME stays real so the CLIs keep
    their sign-ins, and no credential is printed.
- Routes:
  - `model = "claude-cli"`;
  - `model = "codex"`;
  - a local Ollama model, `ollama/qwen3:1.7b` or another installed tool-calling model (IC-74).
- Scenarios, at most 4 short prompts each:
  - S1, steer while streaming: the live row shows `1 queued`; `›` appears at the boundary; the
    relay is in the request. Time from Enter to delivery. CLI routes deliver after the CLI's
    answer.
  - S2, Tab follow-up: it is the next prompt and a second run.
  - S3, typing as an approval arrives: the ask comes after 1 s idle; `y` answers; the draft is
    intact. Then `n use tempdir()`.
  - S4, take-back: two steers, Up, edit, Enter.
  - S5, completion: natural text plus Tab gives nothing; `@obj`, `@dir/`, `peter$`, `@df$`,
    `/mo`, `/skill:` and `!summ` complete.
  - S6, Ctrl-C [a] with a draft and a queued steer: both are listed and recalled with Up.
  - S7, a sub-agent ask while the composer holds a draft.
  - S8, degradations: NO_COLOR=1, TERM=dumb, LANG=C, 50 columns, an Rscript pipe.
  - S10, Ctrl-C under load (amended in the visual review: at load average about 300, 5 of 22 runs of
    0ee69a0 lost a Ctrl-C typed while an answer streamed; none at normal load): the visual scenario's
    run C 30 times beside 2 x nproc busy processes; `Paused` appears within 1 s of every ^C, and `kept
    in history` within 1 s of a ^C at the idle editor. (Amended in the review of Tasks 16-21: it failed,
    6 of 19 runs at load average 40-57, so Task 18's fallback is in: `-isig` in character mode, the
    composer reading byte 0x03, isig back on while in-process R code runs; S10 checks it.)
  - S9, the maintainer's manual checks:
    - RStudio console: the popup appears only on triggers; editor completion works while peter
      waits; a stale line is routed at a question; there is no band.
    - Windows Terminal Rterm: plain prompt and Tab completion.
    - Terminal.app and iTerm2: the OSC 11 reply and the band.
- Record in `dev/progress/P28.md`: transcripts, timings, REQ roles, and pass or fail per scenario
  and route. Each defect becomes Task 29+ with a red test first.

Files: `dev/dogfood/p28-console.R` (new), `dev/progress/P28.md`.

Commit: `docs(progress): P28 live dogfood on claude-cli, codex and ollama`.

## Out of scope

- Mid-turn steering on the CLI routes (Claude Code stream-json input, Codex app-server steer).
- Skipping the remaining calls of a response when a steer arrives (D-242 gives the reason).
- Type-ahead in RStudio, Positron and Windows consoles: R cannot read them while busy.
- Cursor movement inside the composer.
- Shift-Tab mode cycling.
- Terminal titles (OSC 0).
- Truecolor-only colours.
- Per-token colouring of drafts.

## Plan acceptance

| Row | Command | Actual | Status |
|---|---|---|---|
| A1 | `isolated-check.R test 'console-'` | | pending |
| A2 | `isolated-check.R test 'agent-\|session-object\|provider-transform'` | | pending |
| A3 | full `devtools::test()` | | pending |
| A4 | `isolated-check.R lint` (whole package) | | pending |
| A5 | cross-plan checks and `python3 -I dev/ci/check-plans.py` | | pending |
| A6 | `R CMD check --as-cran --no-manual` (0 errors, 0 warnings) | | pending |
| A7 | hosted CI: the pty cases (B, C, D, G, H, I, Enter, Tab, Up, ask-after-idle, band, completion) on the ubuntu and macOS NOT_CRAN lanes; Windows lanes green with them skipped by OS guard | | pending |
| A8 | live dogfood S1-S8 on claude-cli, codex and Ollama (Task 28) | | pending |
| A9 | the maintainer's manual checks (S9): RStudio console, Windows Terminal Rterm, Terminal.app and iTerm2 band | | pending |
